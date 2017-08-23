require 'spec_helper'
require "unit/vm_manager/create/shared_stuff.rb"

describe Bosh::AzureCloud::VMManager do
  include_context "shared stuff for vm manager"

  describe "#create" do
    context "when VM is created" do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Resource group
      context "when the resource group does not exist" do
        before do
          allow(client2).to receive(:get_resource_group).
            with(resource_group_name).
            and_return(nil)
          allow(client2).to receive(:create_network_interface)
        end

        it "should create the resource group" do
          expect(client2).to receive(:create_resource_group).
            with(resource_group_name, location)

          vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          expect(vm_params[:name]).to eq(vm_name)
        end
      end

      # Network Security Group
      context "#network_security_group" do
        context "with the network security group provided in resource_pool" do
          let(:resource_pool) {
            {
              'instance_type'                 => 'Standard_D1',
              'storage_account_name'          => 'dfe03ad623f34d42999e93ca',
              'caching'                       => 'ReadWrite',
              'load_balancer'                 => 'fake-lb-name',
              'security_group'                => 'fake-nsg-name'
            }
          }

          before do
            allow(client2).to receive(:get_network_security_group_by_name).
              with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
              and_return(nil)
            allow(client2).to receive(:get_network_security_group_by_name).
              with(MOCK_RESOURCE_GROUP_NAME, "fake-nsg-name").
              and_return(security_group)
          end

          context "and a heavy stemcell is used" do
            it "should succeed" do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)

              expect(client2).to receive(:create_network_interface).twice
              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
              expect(vm_params[:image_uri]).to eq(stemcell_uri)
              expect(vm_params[:os_type]).to eq(os_type)
            end
          end

          context "and a light stemcell is used" do
            let(:platform_image) {
              {
                'instance_type'                 => 'Standard_D1',
                'storage_account_name'          => 'dfe03ad623f34d42999e93ca',
                'caching'                       => 'ReadWrite',
                'load_balancer'                 => 'fake-lb-name',
                'security_group'                => 'fake-nsg-name'
              }
            }

            before do
              allow(client2).to receive(:get_network_security_group_by_name).
                with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
                and_return(nil)
              allow(client2).to receive(:get_network_security_group_by_name).
                with(MOCK_RESOURCE_GROUP_NAME, "fake-nsg-name").
                and_return(security_group)
            end

            it "should succeed" do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)

              expect(client2).to receive(:create_network_interface).twice
              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end
        end

        context "with the network security group provided in network spec" do
          let(:nsg_name) { "fake-nsg-name-specified-in-network-spec" }
          let(:security_group) {
            {
              :name => nsg_name
            }
          }

          before do
            allow(manual_network).to receive(:security_group).and_return(nsg_name)
            allow(dynamic_network).to receive(:security_group).and_return(nsg_name)
            allow(client2).to receive(:get_network_security_group_by_name).
              with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
              and_return(nil)
            allow(client2).to receive(:get_network_security_group_by_name).
              with(MOCK_RESOURCE_GROUP_NAME, nsg_name).
              and_return(security_group)
          end

          it "should succeed" do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            expect(client2).to receive(:create_network_interface).
              with(resource_group_name, hash_including(:security_group => security_group), any_args).twice
            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context "with the default network security group" do
          it "should succeed" do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context "with the resource group name not provided in the network spec" do
          before do
            allow(client2).to receive(:get_network_subnet_by_name).
              with(MOCK_RESOURCE_GROUP_NAME, "fake-virtual-network-name", "fake-subnet-name").
              and_return(subnet)
          end

          context "when network security group is found in the default resource group" do
            before do
              allow(client2).to receive(:get_network_security_group_by_name).
                with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
                and_return(security_group)
            end

            it "should succeed" do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface).twice
              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end
        end

        context "with the resource group name provided in the network spec" do
          before do
            allow(client2).to receive(:get_network_subnet_by_name).
              with("fake-resource-group-name", "fake-virtual-network-name", "fake-subnet-name").
              and_return(subnet)
          end

          context "when network security group is not found in the specified resource group and found in the default resource group" do
            before do
              allow(client2).to receive(:get_network_security_group_by_name).
                with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
                and_return(security_group)
              allow(client2).to receive(:get_network_security_group_by_name).
                with("fake-resource-group-name", MOCK_DEFAULT_SECURITY_GROUP).
                and_return(nil)
            end

            it "should succeed" do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface).exactly(2).times
              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context "when network security group is found in the specified resource group" do
            before do
              allow(client2).to receive(:get_network_security_group_by_name).
                with("fake-resource-group-name", MOCK_DEFAULT_SECURITY_GROUP).
                and_return(security_group)
            end

            it "should succeed" do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface).twice
              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end
        end
      end

      # Stemcell
      context "#stemcell" do
        context "and a heavy stemcell is used" do
          it "should succeed" do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            expect(client2).to receive(:create_network_interface).exactly(2).times
            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:image_uri]).to eq(stemcell_uri)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end

        context "and a light stemcell is used" do
          let(:platform_image) {
            {
              'publisher' => 'fake-publisher',
              'offer'     => 'fake-offer',
              'sku'       => 'fake-sku',
              'version'   => 'fake-version'
            }
          }

          before do
            allow(stemcell_info).to receive(:is_light_stemcell?).
              and_return(true)
            allow(stemcell_info).to receive(:image_reference).
              and_return(platform_image)
          end

          it "should succeed" do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            expect(client2).to receive(:create_network_interface).twice
            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end
      end

      context "with assign dynamic public IP enabled" do
        let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }
        let(:nic0_params) {
          {
            :name            => "#{vm_name}-0",
            :location        => location,
            :private_ip      => nil,
            :public_ip       => dynamic_public_ip,
            :security_group  => security_group,
            :ipconfig_name   => "ipconfig0"
          }
        }
        let(:tags) { {'user-agent' => 'bosh'} }

        before do
          resource_pool['assign_dynamic_public_ip'] = true
          allow(network_configurator).to receive(:vip_network).
            and_return(nil)
          allow(client2).to receive(:get_public_ip_by_name).
            with(resource_group_name, vm_name).and_return(dynamic_public_ip)
        end

        context "and pip_idle_timeout_in_minutes is set" do
          let(:vm_manager_for_pip) { Bosh::AzureCloud::VMManager.new(
            mock_azure_properties_merge({
              'pip_idle_timeout_in_minutes' => 20
            }), registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager)
          }

          it "creates a public IP and assigns it to the NIC" do
            expect(client2).to receive(:create_public_ip).
              with(resource_group_name, vm_name, location, false, 20)
            expect(client2).to receive(:create_network_interface).
              with(resource_group_name, nic0_params, subnet, tags, load_balancer)

            vm_params = vm_manager_for_pip.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context "and pip_idle_timeout_in_minutes is not set" do
          it "creates a public IP and assigns it to the NIC" do
            expect(client2).to receive(:create_public_ip).
              with(resource_group_name, vm_name, location, false, 4)
            expect(client2).to receive(:create_network_interface).
              with(resource_group_name, nic0_params, subnet, tags, load_balancer)

            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end
      end

      context "with use_managed_disks enabled" do
        let(:availability_set_name) { "#{SecureRandom.uuid}" }

        let(:network_interfaces) {
          [
            {:name => "foo"},
            {:name => "foo"}
          ]
        }

        context "when os type is linux" do
          let(:user_data) {
            {
              :registry          => { :endpoint   => registry_endpoint },
              :server            => { :name       => instance_id_string },
              :dns               => { :nameserver => 'fake-dns'}
            }
          }
          let(:vm_params) {
            {
              :name                => vm_name,
              :location            => location,
              :tags                => { 'user-agent' => 'bosh' },
              :vm_size             => "Standard_D1",
              :ssh_username        => azure_properties_managed['ssh_user'],
              :ssh_cert_data       => azure_properties_managed['ssh_public_key'],
              :custom_data         => Base64.strict_encode64(JSON.dump(user_data)),
              :os_disk             => os_disk_managed,
              :ephemeral_disk      => ephemeral_disk_managed,
              :os_type             => "linux",
              :managed             => true,
              :image_id            => "fake-uri"
            }
          }

          before do
            allow(stemcell_info).to receive(:os_type).and_return('linux')
          end

          it "should succeed" do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).to receive(:create_virtual_machine).
              with(resource_group_name, vm_params, network_interfaces, nil)
            result = vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(result[:name]).to eq(vm_name)
          end
        end

        context "when os type is windows" do
          let(:uuid) { '25900ee5-1215-433c-8b88-f1eaaa9731fe' }
          let(:computer_name) { 'fake-server-name' }
          let(:user_data) {
            {
              :registry          => { :endpoint   => registry_endpoint },
              :'instance-id'     => instance_id_string,
              :server            => { :name       => computer_name },
              :dns               => { :nameserver => 'fake-dns'}
            }
          }
          let(:vm_params) {
            {
              :name                => vm_name,
              :location            => location,
              :tags                => { 'user-agent' => 'bosh' },
              :vm_size             => "Standard_D1",
              :windows_username    => uuid.delete('-')[0,20],
              :windows_password    => 'fake-array',
              :custom_data         => Base64.strict_encode64(JSON.dump(user_data)),
              :os_disk             => os_disk_managed,
              :ephemeral_disk      => ephemeral_disk_managed,
              :os_type             => "windows",
              :managed             => true,
              :image_id            => "fake-uri",
              :computer_name       => computer_name
            }
          }

          before do
            allow(SecureRandom).to receive(:uuid).and_return(uuid)
            expect_any_instance_of(Array).to receive(:shuffle).and_return(['fake-array'])
            allow(stemcell_info).to receive(:os_type).and_return('windows')
            allow(vm_manager2).to receive(:generate_windows_computer_name).and_return(computer_name)
          end

          it "should succeed" do
            expect(client2).to receive(:create_virtual_machine).
              with(resource_group_name, vm_params, network_interfaces, nil)
            expect(SecureRandom).to receive(:uuid).exactly(3).times
            expect {
             vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.not_to raise_error
          end
        end
      end

      context "when AzureAsynchronousError is raised once and AzureAsynchronousError.status is Failed" do
        context " and use_managed_disks is false" do
          it "should succeed" do
            count = 0
            allow(client2).to receive(:create_virtual_machine) do
                count += 1
                count == 1 ? raise(Bosh::AzureCloud::AzureAsynchronousError.new('Failed')) : nil
            end

            expect(client2).to receive(:create_virtual_machine).twice
            expect(client2).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:generate_os_disk_name).with(vm_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:generate_ephemeral_disk_name).with(vm_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files).
              with(storage_account_name, vm_name).once
            expect(client2).not_to receive(:delete_network_interface)

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.not_to raise_error
          end
        end

        context " and use_managed_disks is true" do
          it "should succeed" do
            count = 0
            allow(client2).to receive(:create_virtual_machine) do
                count += 1
                count == 1 ? raise(Bosh::AzureCloud::AzureAsynchronousError.new('Failed')) : nil
            end

            expect(client2).to receive(:create_virtual_machine).twice
            expect(client2).to receive(:delete_virtual_machine).once
            expect(disk_manager2).to receive(:generate_os_disk_name).with(vm_name).once
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name).once
            expect(disk_manager2).to receive(:generate_ephemeral_disk_name).with(vm_name).once
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name).once
            expect(client2).not_to receive(:delete_network_interface)

            expect {
              vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.not_to raise_error
          end
        end
      end

      context "when debug mode is on" do
        let(:azure_properties_debug) {
          mock_azure_properties_merge({
            'debug_mode' => true
          })
        }
        let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties_debug, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager) }

        context 'when vm and default storage account are in different locations' do
          let(:vm_location) { 'fake-vm-location' }
          let(:default_storage_account) {
            {
              :location          => 'fake-storage-account-location',
              :storage_blob_host => 'fake-storage-blob-host'
            }
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
          end

          it "should not enable diagnostics" do
            vm_params = vm_manager.create(instance_id, vm_location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:diag_storage_uri]).to be(nil)
          end
        end

        context 'when vm and default storage account are in same location' do
          let(:vm_location) { location }
          let(:diag_storage_uri) { 'fake-diag-storage-uri' }
          let(:default_storage_account) {
            {
              :location          => location,
              :storage_blob_host => diag_storage_uri
            }
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
          end

          it "should enable diagnostics" do
            vm_params = vm_manager.create(instance_id, vm_location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:diag_storage_uri]).to eq(diag_storage_uri)
          end
        end
      end
    end
  end
end
