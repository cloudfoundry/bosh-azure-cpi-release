require 'spec_helper'
require "unit/vm_manager/create/shared_stuff.rb"

describe Bosh::AzureCloud::VMManager do
  include_context "shared stuff for vm manager"

  describe "#create" do
    context "when VM is not created" do
      context " and client2.create_virtual_machine raises an normal error" do
        context " and no more error occurs" do
          before do
            allow(client2).to receive(:create_virtual_machine).
              and_raise('virtual machine is not created')
          end

          it "should delete vm and nics and then raise an error" do
            expect(client2).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files).
              with(storage_account_name, vm_name).once
            expect(client2).to receive(:delete_network_interface).twice

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error /virtual machine is not created/
          end
        end

        context "and an error occurs when deleting nic" do
          before do
            allow(client2).to receive(:create_virtual_machine).
              and_raise('virtual machine is not created')
            allow(client2).to receive(:delete_network_interface).
              and_raise('cannot delete nic')
          end

          it "should delete vm and nics and then raise an error" do
            expect(client2).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files).
              with(storage_account_name, vm_name).once
            expect(client2).to receive(:delete_network_interface).once

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error /cannot delete nic/
          end
        end
      end

      context " and client2.create_virtual_machine raises an AzureAsynchronousError" do
        context " and AzureAsynchronousError.status is not Failed" do
          before do
            allow(client2).to receive(:create_virtual_machine).
              and_raise(Bosh::AzureCloud::AzureAsynchronousError)
          end

          it "should delete vm and nics and then raise an error" do
            expect(client2).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files).
              with(storage_account_name, vm_name).once
            expect(client2).to receive(:delete_network_interface).twice

            expect {
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error { |error|
              expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
              expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
            }
          end
        end

        context " and AzureAsynchronousError.status is Failed" do
          before do
            allow(client2).to receive(:create_virtual_machine).
              and_raise(Bosh::AzureCloud::AzureAsynchronousError.new('Failed'))
          end

          context " and use_managed_disks is false" do
            context " and ephemeral_disk does not exist" do
              before do
                allow(disk_manager).to receive(:ephemeral_disk).
                  and_return(nil)
              end

              it "should not delete vm and then raise an error" do
                expect(client2).to receive(:create_virtual_machine).exactly(3).times
                expect(client2).to receive(:delete_virtual_machine).twice
                expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).twice
                expect(disk_manager).to receive(:delete_vm_status_files).
                  with(storage_account_name, vm_name).twice
                expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                expect(client2).not_to receive(:delete_network_interface)

                expect {
                  vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.to raise_error { |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                }
              end
            end

            context " and ephemeral_disk exists" do
              context " and no more error occurs" do
                it "should not delete vm and then raise an error" do
                  expect(client2).to receive(:create_virtual_machine).exactly(3).times
                  expect(client2).to receive(:delete_virtual_machine).twice
                  expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).twice
                  expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).twice
                  expect(disk_manager).to receive(:delete_vm_status_files).
                    with(storage_account_name, vm_name).twice
                  expect(client2).not_to receive(:delete_network_interface)

                  expect {
                    vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  }.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context "and an error occurs when deleting vm" do
                before do
                  allow(client2).to receive(:delete_virtual_machine).
                    and_raise('cannot delete the vm')
                end

                it "should not delete vm and then raise an error" do
                  expect(client2).to receive(:create_virtual_machine).once
                  expect(client2).to receive(:delete_virtual_machine).once
                  expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, os_disk_name)
                  expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                  expect(disk_manager).not_to receive(:delete_vm_status_files).
                    with(storage_account_name, vm_name)
                  expect(client2).not_to receive(:delete_network_interface)

                  expect {
                    vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  }.to raise_error /cannot delete the vm/
                end
              end
            end
          end

          context " and use_managed_disks is true" do
            context " and ephemeral_disk does not exist" do
              before do
                allow(disk_manager2).to receive(:ephemeral_disk).
                  and_return(nil)
              end

              it "should not delete vm and then raise an error" do
                expect(client2).to receive(:create_virtual_machine).exactly(3).times
                expect(client2).to receive(:delete_virtual_machine).twice
                expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name).twice
                expect(disk_manager2).not_to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)
                expect(client2).not_to receive(:delete_network_interface)

                expect {
                  vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.to raise_error { |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                }
              end
            end

            context " and ephemeral_disk exists" do
              it "should not delete vm and then raise an error" do
                expect(client2).to receive(:create_virtual_machine).exactly(3).times
                expect(client2).to receive(:delete_virtual_machine).twice
                expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name).twice
                expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name).twice
                expect(client2).not_to receive(:delete_network_interface)

                expect {
                  vm_manager2.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.to raise_error { |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                }
              end
            end
          end
        end
      end
    end
  end
end
