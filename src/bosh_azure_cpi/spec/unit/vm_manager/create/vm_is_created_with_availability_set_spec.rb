require 'spec_helper'
require "unit/vm_manager/create/shared_stuff.rb"

describe Bosh::AzureCloud::VMManager do
  include_context "shared stuff for vm manager"

  describe "#create" do
    context "when VM is created" do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Availability Set
      context "#availability_set" do
        let(:rwlock) { instance_double(Bosh::AzureCloud::Helpers::ReadersWriterLock) }
        before do
          allow(Bosh::AzureCloud::Helpers::ReadersWriterLock).to receive(:new).and_return(rwlock)
          allow(rwlock).to receive(:acquire_read_lock)
          allow(rwlock).to receive(:release_read_lock)
        end
        let(:create_avset_lock) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
        before do
          allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(create_avset_lock)
          allow(create_avset_lock).to receive(:lock).and_return(true)
          allow(create_avset_lock).to receive(:unlock)
        end

        context "when it fails to acquire the readers lock" do
          let(:env) { nil }
          let(:availability_set_name) { "#{SecureRandom.uuid}" }
          let(:resource_pool) {
            {
              'instance_type' => 'Standard_D1',
              'availability_set' => availability_set_name,
            }
          }

          before do
            allow(rwlock).to receive(:acquire_read_lock).and_raise(Bosh::AzureCloud::Helpers::LockTimeoutError)
          end

          it "should not delete VM and then raise an error" do
            expect(File).to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).to receive(:delete_network_interface).exactly(2).times

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error /LockTimeoutError/
          end
        end

        context "when availability set is not created" do
          let(:env) { nil }
          let(:availability_set_name) { "#{SecureRandom.uuid}" }
          let(:resource_pool) {
            {
              'instance_type' => 'Standard_D1',
              'availability_set' => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count' => 3,
            }
          }

          before do
            allow(client2).to receive(:get_availability_set_by_name).
              with(resource_group_name, availability_set_name).
              and_return(nil)
            allow(rwlock).to receive(:acquire_read_lock)
            allow(create_avset_lock).to receive(:lock).and_return(true)
            allow(client2).to receive(:create_availability_set).
              and_raise("availability set is not created")
          end

          it "should delete nics and then raise an error" do
            expect(File).to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
            expect(create_avset_lock).not_to receive(:unlock)
            expect(rwlock).to receive(:release_read_lock)
            expect(client2).to receive(:delete_virtual_machine)
            expect(client2).to receive(:delete_network_interface).exactly(2).times

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error /Failed to create the availability set `#{availability_set_name}' in the resource group `#{resource_group_name}'/
          end
        end

        context "with env is nil and availability_set is specified in resource_pool" do
          let(:env) { nil }
          let(:availability_set_name) { "#{SecureRandom.uuid}" }
          let(:resource_pool) {
            {
              'instance_type'                => 'Standard_D1',
              'availability_set'             => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count'  => 3,
            }
          }
          let(:avset_params) {
            {
              :name                         => resource_pool['availability_set'],
              :location                     => location,
              :tags                         => {'user-agent' => 'bosh'},
              :platform_update_domain_count => resource_pool['platform_update_domain_count'],
              :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'],
              :managed                      => false
            }
          }

          before do
            allow(client2).to receive(:get_availability_set_by_name).
              with(resource_group_name, resource_pool['availability_set']).
              and_return(nil)
          end

          it "should create availability set with the name specified in resource_pool" do
            expect(client2).to receive(:create_availability_set).
              with(resource_group_name, avset_params)
            expect(client2).to receive(:create_network_interface).twice

            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context "with bosh.group specified in env" do
          context "when availability_set is specified in resource_pool" do
            let(:env) {
              {
                'bosh' => {
                  'group' => "bosh-group-#{SecureRandom.uuid}"
                }
              }
            }
            let(:availability_set_name) { "#{SecureRandom.uuid}" }
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3,
              }
            }
            let(:avset_params) {
              {
                :name                         => resource_pool['availability_set'],
                :location                     => location,
                :tags                         => {'user-agent' => 'bosh'},
                :platform_update_domain_count => resource_pool['platform_update_domain_count'],
                :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'],
                :managed                      => false
              }
            }

            before do
              allow(client2).to receive(:get_availability_set_by_name).
                with(resource_group_name, resource_pool['availability_set']).
                and_return(nil)
            end

            it "should create availability set with the name specified in resource_pool" do
              expect(client2).to receive(:create_availability_set).
                with(resource_group_name, avset_params)

              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context "when availability_set is not specified in resource_pool" do
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1'
              }
            }
            let(:avset_params) {
              {
                :location                     => location,
                :tags                         => {'user-agent' => 'bosh'},
                :platform_update_domain_count => 5,
                :platform_fault_domain_count  => 3,
                :managed                      => false
              }
            }

            context "when the length of availability_set name equals to 80" do
              let(:env) {
                {
                  'bosh' => {'group' => 'group' * 16}
                }
              }

              before do
                avset_params[:name] = env['bosh']['group']
                allow(client2).to receive(:get_availability_set_by_name).
                  with(resource_group_name, env['bosh']['group']).
                  and_return(nil)
              end

              it "should create availability set and use value of env.bosh.group as its name" do
                expect(client2).to receive(:create_availability_set).
                  with(resource_group_name, avset_params)

                vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context "when the length of availability_set name is greater than 80" do
              let(:env) {
                {
                  'bosh' => {'group' => 'a' * 80 + 'group' * 8}
                }
              }

              before do
                # 21d9858fb04d8ba39cdacdc926c5415e is MD5 of the availability_set name ('a' * 80 + 'group' * 8)
                avset_params[:name] = "az-21d9858fb04d8ba39cdacdc926c5415e-#{'group' * 8}"
                allow(client2).to receive(:get_availability_set_by_name).
                  and_return(nil)
              end

              it "should create availability set with a truncated value of env.bosh.group as its name" do
                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)

                vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end
          end
        end

        context "when the availability set doesn't exist" do
          let(:availability_set_name) { "#{SecureRandom.uuid}" }
          before do
            allow(client2).to receive(:get_availability_set_by_name).
              with(resource_group_name, availability_set_name).
              and_return(nil)
          end

          context "when platform_update_domain_count and platform_fault_domain_count are set" do
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 4,
                'platform_fault_domain_count' => 1
              }
            }
            let(:avset_params) {
              {
                :name                         => resource_pool['availability_set'],
                :location                     => location,
                :tags                         => {'user-agent' => 'bosh'},
                :platform_update_domain_count => 4,
                :platform_fault_domain_count  => 1
              }
            }

            context "when the availability set is unmanaged" do
              before do
                avset_params[:managed] = false
              end

              it "should create the unmanaged availability set" do
                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                expect(client2).to receive(:create_network_interface).twice

                vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context "when the availability set is managed" do
              before do
                avset_params[:managed] = true
              end

              it "should create the managed availability set" do
                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                expect(client2).to receive(:create_network_interface).twice

                vm_params = vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end
          end

          context "when platform_update_domain_count and platform_fault_domain_count are not set" do
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name
              }
            }
            let(:avset_params) {
              {
                :name     => resource_pool['availability_set'],
                :location => location,
                :tags     => {'user-agent' => 'bosh'}
              }
            }

            context "when the environment is not AzureStack" do
              context "when the availability set is unmanaged" do
                before do
                  avset_params[:platform_update_domain_count] = 5
                  avset_params[:platform_fault_domain_count]  = 3
                  avset_params[:managed]                      = false
                end

                it "should create the unmanaged availability set" do
                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end

              context "when the availability set is managed" do
                before do
                  avset_params[:platform_update_domain_count] = 5
                  avset_params[:platform_fault_domain_count]  = 2
                  avset_params[:managed]                      = true
                end

                it "should create the managed availability set" do
                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end
            end

            context "when the environment is AzureStack" do
              # VM manager for AzureStack
              let(:azure_properties_azure_stack) {
                mock_azure_properties_merge({
                  'environment' => 'AzureStack'
                })
              }
              let(:vm_manager_azure_stack) { Bosh::AzureCloud::VMManager.new(azure_properties_azure_stack, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager) }

              # Only unmanaged availability set is supported on AzureStack
              context "when the availability set is unmanaged" do
                before do
                  avset_params[:platform_update_domain_count] = 1
                  avset_params[:platform_fault_domain_count]  = 1
                  avset_params[:managed]                      = false
                end

                it "should create the unmanaged availability set" do
                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager_azure_stack.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end
            end
          end
        end

        context "when the availability set exists" do
          context "when the availability set is in a different location" do
            let(:env) { nil }
            let(:availability_set_name) { "#{SecureRandom.uuid}" }
            let(:availability_set) {
              {
                :name => availability_set_name,
                :virtual_machines => [
                  "fake-vm-id-1",
                  "fake-vm-id-2"
                ],
                :location => "different-from-#{location}"
              }
            }
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3,
              }
            }

            before do
              allow(client2).to receive(:get_availability_set_by_name).
                with(resource_group_name, resource_pool['availability_set']).
                and_return(availability_set)
            end

            it "should not create the availability set and then raise an error" do
              expect(client2).not_to receive(:create_availability_set)
              expect(client2).to receive(:delete_virtual_machine)
              expect(client2).to receive(:delete_network_interface).exactly(2).times

              expect {
                vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              }.to raise_error /create_availability_set - the availability set `#{availability_set_name}' already exists, but in a different location/
            end
          end

          context "when the managed property is aligned with @use_managed_disks" do
            let(:env) { nil }
            let(:availability_set_name) { "#{SecureRandom.uuid}" }
            let(:availability_set) {
              {
                :name => availability_set_name,
                :virtual_machines => [
                  "fake-vm-id-1",
                  "fake-vm-id-2"
                ],
                :location => "#{location}"
              }
            }
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3,
              }
            }

            before do
              allow(client2).to receive(:get_availability_set_by_name).
                with(resource_group_name, resource_pool['availability_set']).
                and_return(availability_set)
            end

            it "should not create availability set" do
              expect(client2).not_to receive(:create_availability_set)

              vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context "when the managed property is not aligned with @use_managed_disks" do
            let(:availability_set_name) { "#{SecureRandom.uuid}" }
            let(:resource_pool) {
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
              }
            }

            let(:existing_avset) {
              {
                :name                         => resource_pool['availability_set'],
                :location                     => location,
                :tags                         => {'user-agent' => 'bosh'},
                :platform_update_domain_count => 5,
                :platform_fault_domain_count  => 3,
                :managed                      => false
              }
            }
            let(:avset_params) {
              {
                :name                         => existing_avset[:name],
                :location                     => existing_avset[:location],
                :tags                         => existing_avset[:tags],
                :platform_update_domain_count => existing_avset[:platform_update_domain_count],
                :platform_fault_domain_count  => existing_avset[:platform_fault_domain_count],
                :managed                      => true
              }
            }

            before do
              allow(client2).to receive(:get_availability_set_by_name).
                with(resource_group_name, resource_pool['availability_set']).
                and_return(existing_avset)
            end

            it "should update the managed property of the availability set" do
              expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
              expect(client2).to receive(:create_network_interface).twice

              vm_params = vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end
        end
      end
    end
  end
end
