# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - resource_group_name
  #   - default_security_group
  describe '#create' do
    context 'when VM is created' do
      before do
        allow(azure_client).to receive(:create_virtual_machine)
        allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
        allow(vm_manager2).to receive(:_get_stemcell_info).and_return(stemcell_info)
      end

      # Dynamic Public IP
      context 'with assign dynamic public IP enabled' do
        let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }
        let(:tags) { { 'user-agent' => 'bosh' } }

        before do
          vm_props.assign_dynamic_public_ip = true
          allow(network_configurator).to receive(:vip_network)
            .and_return(nil)
          allow(azure_client).to receive(:get_public_ip_by_name)
            .with(MOCK_RESOURCE_GROUP_NAME, vm_name).and_return(dynamic_public_ip)
        end

        context 'and pip_idle_timeout_in_minutes is set' do
          let(:idle_timeout) { 20 }
          let(:vm_manager_for_pip) do
            Bosh::AzureCloud::VMManager.new(
              mock_azure_config_merge(
                'pip_idle_timeout_in_minutes' => idle_timeout
              ), registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager
            )
          end
          let(:public_ip_params) do
            {
              name: vm_name,
              location: location,
              is_static: false,
              idle_timeout_in_minutes: idle_timeout
            }
          end

          before do
            allow(vm_manager_for_pip).to receive(:_get_stemcell_info).and_return(stemcell_info)
            allow(vm_manager_for_pip).to receive(:get_storage_account_from_vm_properties)
              .and_return(name: storage_account_name)
          end

          it 'creates a public IP and assigns it to the primary NIC' do
            expect(azure_client).to receive(:create_public_ip)
              .with(MOCK_RESOURCE_GROUP_NAME, public_ip_params)
            expect(azure_client).to receive(:create_network_interface)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(
                                                name: "#{vm_name}-0",
                                                public_ip: dynamic_public_ip,
                                                subnet: subnet,
                                                tags: tags,
                                                load_balancer: load_balancer,
                                                application_gateway: application_gateway
                                              )).once

            _, vm_params = vm_manager_for_pip.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context 'and pip_idle_timeout_in_minutes is not set' do
          let(:default_idle_timeout) { 4 }
          let(:public_ip_params) do
            {
              name: vm_name,
              location: location,
              is_static: false,
              idle_timeout_in_minutes: default_idle_timeout
            }
          end

          it 'creates a public IP and assigns it to the NIC' do
            expect(azure_client).to receive(:create_public_ip)
              .with(MOCK_RESOURCE_GROUP_NAME, public_ip_params)
            expect(azure_client).to receive(:create_network_interface)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(
                                                public_ip: dynamic_public_ip,
                                                subnet: subnet,
                                                tags: tags,
                                                load_balancer: load_balancer,
                                                application_gateway: application_gateway
                                              ))

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end
      end

      context 'with use_managed_disks enabled' do
        let(:availability_set_name) { SecureRandom.uuid.to_s }

        let(:network_interfaces) do
          [
            { name: 'foo' },
            { name: 'foo' }
          ]
        end

        context 'when os type is linux' do
          let(:user_data) do
            {
              registry: { endpoint: registry_endpoint },
              server: { name: instance_id_string },
              dns: { nameserver: 'fake-dns' }
            }
          end
          let(:vm_params) do
            {
              name: vm_name,
              location: location,
              tags: { 'user-agent' => 'bosh' },
              vm_size: 'Standard_D1',
              ssh_username: azure_config_managed.ssh_user,
              ssh_cert_data: azure_config_managed.ssh_public_key,
              custom_data: Base64.strict_encode64(JSON.dump(user_data)),
              os_disk: os_disk_managed,
              ephemeral_disk: ephemeral_disk_managed,
              os_type: 'linux',
              managed: true,
              image_id: 'fake-uri'
            }
          end

          before do
            allow(stemcell_info).to receive(:os_type).and_return('linux')
          end

          it 'should succeed' do
            expect(instance_id).to receive(:resource_group_name)
              .and_return(MOCK_RESOURCE_GROUP_NAME)
            expect(Bosh::AzureCloud::InstanceId).to receive(:create)
              .with(MOCK_RESOURCE_GROUP_NAME, agent_id)
              .and_return(instance_id)
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_params, network_interfaces, nil)
            _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context 'when os type is windows' do
          let(:uuid) { '25900ee5-1215-433c-8b88-f1eaaa9731fe' }
          let(:computer_name) { 'fake-server-name' }
          let(:user_data) do
            {
              registry: { endpoint: registry_endpoint },
              'instance-id': instance_id_string,
              server: { name: computer_name },
              dns: { nameserver: 'fake-dns' }
            }
          end
          let(:vm_params) do
            {
              name: vm_name,
              location: location,
              tags: { 'user-agent' => 'bosh' },
              vm_size: 'Standard_D1',
              windows_username: uuid.delete('-')[0, 20],
              windows_password: 'fake-array',
              custom_data: Base64.strict_encode64(JSON.dump(user_data)),
              os_disk: os_disk_managed,
              ephemeral_disk: ephemeral_disk_managed,
              os_type: 'windows',
              managed: true,
              image_id: 'fake-uri',
              computer_name: computer_name
            }
          end

          before do
            allow(SecureRandom).to receive(:uuid).and_return(uuid)
            expect_any_instance_of(Array).to receive(:shuffle).and_return(['fake-array'])
            allow(stemcell_info).to receive(:os_type).and_return('windows')
            allow(vm_manager2).to receive(:generate_windows_computer_name).and_return(computer_name)
          end

          it 'should succeed' do
            expect(instance_id).to receive(:resource_group_name)
              .and_return(MOCK_RESOURCE_GROUP_NAME)
            expect(Bosh::AzureCloud::InstanceId).to receive(:create)
              .with(MOCK_RESOURCE_GROUP_NAME, agent_id)
              .and_return(instance_id)
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_params, network_interfaces, nil)
            expect(SecureRandom).to receive(:uuid).exactly(3).times
            expect do
              vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.not_to raise_error
          end
        end
      end

      context 'when AzureAsynchronousError is raised once and AzureAsynchronousError.status is Failed' do
        context ' and use_managed_disks is false' do
          it 'should succeed' do
            count = 0
            allow(azure_client).to receive(:create_virtual_machine) do
              count += 1
              raise Bosh::AzureCloud::AzureAsynchronousError, 'Failed' if count == 1

              nil
            end

            expect(azure_client).to receive(:create_virtual_machine).twice
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:generate_os_disk_name).with(vm_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:generate_ephemeral_disk_name).with(vm_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files)
              .with(storage_account_name, vm_name).once
            expect(azure_client).not_to receive(:delete_network_interface)

            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.not_to raise_error
          end
        end

        context ' and use_managed_disks is true' do
          it 'should succeed' do
            count = 0
            allow(azure_client).to receive(:create_virtual_machine) do
              count += 1
              raise Bosh::AzureCloud::AzureAsynchronousError, 'Failed' if count == 1

              nil
            end

            expect(azure_client).to receive(:create_virtual_machine).twice
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(disk_manager2).to receive(:generate_os_disk_name).with(vm_name).once
            expect(disk_manager2).to receive(:delete_disk).with(MOCK_RESOURCE_GROUP_NAME, os_disk_name).once
            expect(disk_manager2).to receive(:generate_ephemeral_disk_name).with(vm_name).once
            expect(disk_manager2).to receive(:delete_disk).with(MOCK_RESOURCE_GROUP_NAME, ephemeral_disk_name).once
            expect(azure_client).not_to receive(:delete_network_interface)

            expect do
              vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.not_to raise_error
          end
        end
      end
    end
  end
end
