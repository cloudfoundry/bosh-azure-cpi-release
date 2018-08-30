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

      # Resource group
      context 'when the resource group does not exist' do
        before do
          allow(azure_client).to receive(:get_resource_group)
            .with(MOCK_RESOURCE_GROUP_NAME)
            .and_return(nil)
          allow(azure_client).to receive(:create_network_interface)
        end

        it 'should create the resource group' do
          expect(azure_client).to receive(:create_resource_group)
            .with(MOCK_RESOURCE_GROUP_NAME, location)

          _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
          expect(vm_params[:name]).to eq(vm_name)
        end
      end

      # Application Security Groups
      context '#application_security_groups' do
        context 'when the application security groups are specified in network specs' do
          let(:asg_1_name_in_network_spec) { 'fake-asg-1-name-specified-in-network-spec' }
          let(:asg_1_in_network_spec) do
            {
              name: asg_1_name_in_network_spec
            }
          end
          let(:asg_2_name_in_network_spec) { 'fake-asg-2-name-specified-in-network-spec' }
          let(:asg_2_in_network_spec) do
            {
              name: asg_2_name_in_network_spec
            }
          end
          let(:asg_names_in_network_spec) { [asg_1_name_in_network_spec, asg_2_name_in_network_spec] }
          let(:asgs_in_network_spec) { [asg_1_in_network_spec, asg_2_in_network_spec] }

          before do
            allow(manual_network).to receive(:application_security_groups).and_return(asg_names_in_network_spec)
            allow(dynamic_network).to receive(:application_security_groups).and_return(asg_names_in_network_spec)
            allow(azure_client).to receive(:get_application_security_group_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, asg_1_name_in_network_spec)
              .and_return(asg_1_in_network_spec)
            allow(azure_client).to receive(:get_application_security_group_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, asg_2_name_in_network_spec)
              .and_return(asg_2_in_network_spec)
          end

          it 'should assign the application security groups specified in network specs to the network interface' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)
            expect(azure_client).to receive(:get_application_security_group_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, asg_1_name_in_network_spec)
              .and_return(asg_1_in_network_spec).twice
            expect(azure_client).to receive(:get_application_security_group_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, asg_2_name_in_network_spec)
              .and_return(asg_2_in_network_spec).twice
            expect(azure_client).to receive(:create_network_interface)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(application_security_groups: asgs_in_network_spec), any_args).twice
            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.not_to raise_error
          end

          context ' and vm_properties' do
            let(:asg_1_name_in_vm_properties) { 'fake-asg-1-name-specified-in-resource-pool' }
            let(:asg_1_in_vm_properties) do
              {
                name: asg_1_name_in_vm_properties
              }
            end
            let(:asg_2_name_in_vm_properties) { 'fake-asg-2-name-specified-in-resource-pool' }
            let(:asg_2_in_vm_properties) do
              {
                name: asg_2_name_in_vm_properties
              }
            end
            let(:asg_names_in_vm_properties) { [asg_1_name_in_vm_properties, asg_2_name_in_vm_properties] }
            let(:asgs_in_vm_properties) { [asg_1_in_vm_properties, asg_2_in_vm_properties] }
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'application_security_groups' => asg_names_in_vm_properties
              )
            end

            before do
              allow(manual_network).to receive(:application_security_groups).and_return(asg_names_in_vm_properties)
              allow(dynamic_network).to receive(:application_security_groups).and_return(asg_names_in_vm_properties)
              allow(azure_client).to receive(:get_application_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, asg_1_name_in_vm_properties)
                .and_return(asg_1_in_vm_properties)
              allow(azure_client).to receive(:get_application_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, asg_2_name_in_vm_properties)
                .and_return(asg_2_in_vm_properties)
            end

            it 'should assign the application security groups specified in vm_types or vm_extensions to the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:get_application_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, asg_1_name_in_vm_properties)
                .and_return(asg_1_in_vm_properties).twice
              expect(azure_client).to receive(:get_application_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, asg_2_name_in_vm_properties)
                .and_return(asg_2_in_vm_properties).twice
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(application_security_groups: asgs_in_vm_properties), any_args).twice
              expect(azure_client).not_to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(application_security_groups: asgs_in_network_spec), any_args)
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end
        end

        # The cases in the below context doesn't care where the asg names is specified.
        context '#resource_group_for_application_security_group' do
          let(:asg_name) { 'fake-asg-name' }
          let(:asg) do
            {
              name: asg_name
            }
          end
          let(:asg_names) { [asg_name] }
          let(:asgs) { [asg] }
          let(:nsg_name_in_vm_properties) { 'fake-nsg-name-specified-in-resource-pool' }
          let(:security_group_in_vm_properties) do
            {
              name: nsg_name_in_vm_properties
            }
          end
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1',
              'security_group' => nsg_name_in_vm_properties,
              'application_security_groups' => asg_names
            )
          end

          context 'when the resource group name is not specified in the network spec' do
            before do
              allow(manual_network).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
              allow(dynamic_network).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
              allow(azure_client).to receive(:get_network_subnet_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'fake-subnet-name')
                .and_return(subnet)
              allow(azure_client).to receive(:get_network_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, nsg_name_in_vm_properties)
                .and_return(security_group_in_vm_properties)
            end

            it 'should find the application security group in the default resource group' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:get_application_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, asg_name)
                .and_return(asg).twice
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(application_security_groups: asgs), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when the resource group name is specified in the network spec' do
            let(:rg_name_for_asg) { 'resource-group-name-for-application-security-group' }
            before do
              allow(manual_network).to receive(:resource_group_name).and_return(rg_name_for_asg)
              allow(dynamic_network).to receive(:resource_group_name).and_return(rg_name_for_asg)
              allow(azure_client).to receive(:get_network_subnet_by_name)
                .with(rg_name_for_asg, 'fake-virtual-network-name', 'fake-subnet-name')
                .and_return(subnet)
              allow(azure_client).to receive(:get_network_security_group_by_name)
                .with(rg_name_for_asg, nsg_name_in_vm_properties)
                .and_return(security_group_in_vm_properties)
            end

            context 'when application security group is found in the specified resource group' do
              before do
                allow(vm_props).to receive(:resource_group_name).and_return(rg_name_for_asg)
              end

              it 'should assign the application security group to the network interface' do
                expect(azure_client).not_to receive(:delete_virtual_machine)
                expect(azure_client).not_to receive(:delete_network_interface)
                expect(azure_client).to receive(:get_application_security_group_by_name)
                  .with(rg_name_for_asg, asg_name)
                  .and_return(asg).twice
                expect(azure_client).not_to receive(:get_application_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, asg_name)
                expect(azure_client).to receive(:create_network_interface)
                  .with(rg_name_for_asg, hash_including(application_security_groups: asgs), any_args).twice
                expect do
                  vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                end.not_to raise_error
              end
            end

            context 'when application security group is not found in the specified resource group, but found in the default resource group' do
              it 'should assign the application security group to the network interface' do
                expect(azure_client).not_to receive(:delete_virtual_machine)
                expect(azure_client).not_to receive(:delete_network_interface)
                expect(azure_client).to receive(:get_application_security_group_by_name)
                  .with(rg_name_for_asg, asg_name)
                  .and_return(nil).twice
                expect(azure_client).to receive(:get_application_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, asg_name)
                  .and_return(asg).twice
                expect(azure_client).to receive(:create_network_interface)
                  .with(MOCK_RESOURCE_GROUP_NAME, hash_including(application_security_groups: asgs), any_args).twice
                expect do
                  vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                end.not_to raise_error
              end
            end

            context 'when application security group is not found in neither the specified resource group nor the default resource group' do
              it 'should raise an error' do
                expect(azure_client).not_to receive(:delete_virtual_machine)
                expect(azure_client).not_to receive(:delete_network_interface)
                expect(azure_client).to receive(:get_application_security_group_by_name)
                  .with(rg_name_for_asg, asg_name)
                  .and_return(nil)
                expect(azure_client).to receive(:get_application_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, asg_name)
                  .and_return(nil)
                expect(azure_client).not_to receive(:create_network_interface)
                expect(azure_client).to receive(:list_network_interfaces_by_keyword).and_return([])
                expect(azure_client).not_to receive(:delete_network_interface)
                expect do
                  vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                end.to raise_error /Cannot find the application security group '#{asg_name}'/
              end
            end
          end
        end
      end

      # IP Forwarding
      context '#ip_forwarding' do
        context 'when ip forwarding is disbaled in network specs' do
          before do
            allow(manual_network).to receive(:ip_forwarding).and_return(false)
            allow(dynamic_network).to receive(:ip_forwarding).and_return(false)
          end

          context 'when ip forwarding is not specified in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1'
              )
            end
            it 'should disable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when ip forwarding is disabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'ip_forwarding' => false
              )
            end
            it 'should disable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when ip forwarding is enabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'ip_forwarding' => true
              )
            end
            it 'should enable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end
        end

        context 'when ip forwarding is enabled in network specs' do
          before do
            allow(manual_network).to receive(:ip_forwarding).and_return(true)
            allow(dynamic_network).to receive(:ip_forwarding).and_return(true)
          end

          context 'when ip forwarding is not specified in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1'
              )
            end
            it 'should enable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when ip forwarding is disabled in vm_vm_types or vm_extensionsproperties' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'ip_forwarding' => false
              )
            end
            it 'should disable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when ip forwarding is enabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'ip_forwarding' => true
              )
            end
            it 'should enable ip forwarding on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_ip_forwarding: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end
        end
      end

      # Accelerated Networking
      context '#accelerated_networking' do
        context 'when accelerated networking is disbaled in network specs' do
          before do
            allow(manual_network).to receive(:accelerated_networking).and_return(false)
            allow(dynamic_network).to receive(:accelerated_networking).and_return(false)
          end

          context 'when accelerated networking is not specified in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1'
              )
            end
            it 'should disable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is disabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => false
              )
            end
            it 'should disable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is enabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => true
              )
            end
            it 'should enable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end
        end

        context 'when accelerated networking is enabled in network specs' do
          before do
            allow(manual_network).to receive(:accelerated_networking).and_return(true)
            allow(dynamic_network).to receive(:accelerated_networking).and_return(true)
          end

          context 'when accelerated networking is not specified in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1'
              )
            end
            it 'should enable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is disabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => false
              )
            end
            it 'should disable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is enabled in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => true
              )
            end
            it 'should enable accelerated networking on the network interface' do
              expect(azure_client).not_to receive(:delete_virtual_machine)
              expect(azure_client).not_to receive(:delete_network_interface)
              expect(azure_client).to receive(:create_network_interface)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
              end.not_to raise_error
            end
          end
        end
      end

      # Stemcell
      context '#stemcell' do
        context 'when a heavy stemcell is used' do
          it 'should succeed' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)

            expect(azure_client).to receive(:create_network_interface).exactly(2).times
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:image_uri]).to eq(stemcell_uri)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end

        context 'when a light stemcell is used' do
          let(:platform_image) do
            {
              'publisher' => 'fake-publisher',
              'offer' => 'fake-offer',
              'sku' => 'fake-sku',
              'version' => 'fake-version'
            }
          end

          before do
            allow(stemcell_info).to receive(:is_light_stemcell?)
              .and_return(true)
            allow(stemcell_info).to receive(:image_reference)
              .and_return(platform_image)
          end

          it 'should succeed' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)

            expect(azure_client).to receive(:create_network_interface).twice
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end
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
            allow(Bosh::AzureCloud::InstanceId).to receive(:create)
              .with(vm_props.resource_group_name, bosh_vm_meta.agent_id)
              .and_return(instance_id)
            allow(instance_id).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
          end

          it 'should succeed' do
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
            allow(Bosh::AzureCloud::InstanceId).to receive(:create)
              .with(vm_props.resource_group_name, bosh_vm_meta.agent_id)
              .and_return(instance_id)
            allow(instance_id).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
          end

          it 'should succeed' do
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

      # Boot diagnostics
      context 'when enable_vm_boot_diagnostics is enabled' do
        context 'and when environment is not AzureStack' do
          let(:azure_config_debug) do
            mock_azure_config_merge(
              'enable_vm_boot_diagnostics' => true
            )
          end
          let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_config_debug, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }

          let(:vm_location) { location }
          let(:diag_storage_uri) { 'fake-diag-storage-uri' }
          let(:storage_account) do
            {
              location: location,
              storage_blob_host: diag_storage_uri
            }
          end

          it 'should enable diagnostics' do
            expect(storage_account_manager).to receive(:get_or_create_diagnostics_storage_account)
              .with(location)
              .and_return(storage_account)
            _, vm_params = vm_manager.create(bosh_vm_meta, vm_location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:diag_storage_uri]).to eq(diag_storage_uri)
          end
        end

        context 'and when environment is AzureStack' do
          let(:azure_config_debug) do
            mock_azure_config_merge(
              'enable_vm_boot_diagnostics' => true,
              'environment' => 'AzureStack'
            )
          end
          let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_config_debug, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }

          let(:vm_location) { location }

          it 'should not enable diagnostics' do
            _, vm_params = vm_manager.create(bosh_vm_meta, vm_location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:diag_storage_uri]).to be(nil)
          end
        end
      end

      # Availability Zones
      context 'with availability zone specified' do
        let(:availability_zone) { '1' }

        before do
          vm_props.availability_zone = availability_zone

          allow(network_configurator).to receive(:vip_network)
            .and_return(nil)
        end

        context 'and assign_dynamic_public_ip is true' do
          let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }

          before do
            vm_props.assign_dynamic_public_ip = true
            allow(azure_client).to receive(:get_public_ip_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_name).and_return(dynamic_public_ip)
          end

          it 'creates public IP and virtual machine in the specified zone' do
            expect(azure_client).to receive(:create_public_ip)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(
                                                zone: availability_zone
                                              )).once
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and assign_dynamic_public_ip is not set' do
          it 'creates virtual machine in the specified zone' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and availability_zone is an integer' do
          before do
            vm_props.availability_zone = 1
          end

          it 'convert availability_zone to string' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: '1'),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq('1')
          end
        end
      end
    end
  end
end
