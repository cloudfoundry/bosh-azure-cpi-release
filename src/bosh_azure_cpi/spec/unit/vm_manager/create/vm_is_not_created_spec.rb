# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    before do
      allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
      allow(vm_manager2).to receive(:_get_stemcell_info).and_return(stemcell_info)
    end

    context 'when VM is not created' do
      context 'and azure_client.create_virtual_machine raises an normal error' do
        context 'and no more error occurs' do
          before do
            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise('virtual machine is not created')
          end

          it 'should delete vm and nics and then raise an error' do
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files)
              .with(storage_account_name, vm_name).once
            expect(azure_client).to receive(:delete_network_interface).twice

            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.to raise_error /virtual machine is not created/
          end
        end

        context 'when vm is created in an availability set' do
          let(:availability_set_name) { 'fake-avset-name' }
          let(:availability_set) do
            {
              name: availability_set_name,
              location: location,
              virtual_machines: []
            }
          end

          before do
            vm_props.availability_set = Bosh::AzureCloud::AvailabilitySetConfig.new(
              availability_set_name,
              5,
              1
            )

            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise('virtual machine is not created')
            allow(azure_client).to receive(:get_availability_set_by_name)
              .and_return(availability_set)
          end

          it 'should delete vm, avset and nics and then raise an error' do
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(azure_client).to receive(:delete_availability_set).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files)
              .with(storage_account_name, vm_name).once
            expect(azure_client).to receive(:delete_network_interface).twice
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set[:name]}", File::LOCK_EX) # get_or_create_availability_set
              .and_call_original
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set[:name]}", File::LOCK_SH) # create vm, delete vm
              .and_call_original
              .twice
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set[:name]}", File::LOCK_EX | File::LOCK_NB) # delete empty avset
              .and_call_original
            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.to raise_error /virtual machine is not created/
          end
        end

        context 'and an error occurs when deleting nic' do
          before do
            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise('virtual machine is not created')
            allow(azure_client).to receive(:delete_network_interface)
              .and_raise('cannot delete nic')
          end

          it 'should delete vm and nics and then raise an error' do
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files)
              .with(storage_account_name, vm_name).once
            expect(azure_client).to receive(:delete_network_interface).once

            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.to raise_error /cannot delete nic/
          end
        end
      end

      context 'and azure_client.create_virtual_machine raises an AzureAsynchronousError' do
        context 'and AzureAsynchronousError.status is not Failed' do
          before do
            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise(Bosh::AzureCloud::AzureAsynchronousError)
          end

          it 'should delete vm and nics and then raise an error' do
            expect(azure_client).to receive(:delete_virtual_machine).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).once
            expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).once
            expect(disk_manager).to receive(:delete_vm_status_files)
              .with(storage_account_name, vm_name).once
            expect(azure_client).to receive(:delete_network_interface).twice

            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.to raise_error { |error|
              expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
              expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
            }
          end
        end

        context 'and AzureAsynchronousError.status is Failed' do
          before do
            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise(Bosh::AzureCloud::AzureAsynchronousError.new('Failed'), 'fake error message')
          end

          context 'and keep_failed_vms is false in global configuration' do
            context 'and use_managed_disks is false' do
              context 'and VM is in an availability set' do
                let(:availability_set_name) { 'fake-avset-name' }
                let(:availability_set) do
                  {
                    name: availability_set_name,
                    location: location,
                    virtual_machines: []
                  }
                end

                before do
                  vm_props.availability_set = Bosh::AzureCloud::AvailabilitySetConfig.new(
                    availability_set_name,
                    5,
                    1
                  )
                  allow(azure_client).to receive(:get_availability_set_by_name)
                    .and_return(availability_set)

                  allow(disk_manager).to receive(:delete_disk)
                end

                it 'should delete vm, availability set and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_network_interface).twice
                  expect(azure_client).to receive(:delete_availability_set).once

                  expect do
                    vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context 'and ephemeral_disk does not exist' do
                before do
                  allow(disk_manager).to receive(:ephemeral_disk)
                    .and_return(nil)
                end

                it 'should delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                  expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).exactly(3).times
                  expect(disk_manager).to receive(:delete_vm_status_files)
                    .with(storage_account_name, vm_name).exactly(3).times
                  expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                  expect(azure_client).to receive(:delete_network_interface).twice

                  expect do
                    vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context 'and ephemeral_disk exists' do
                context 'and all the vm resources are deleted successfully' do
                  it 'should delete vm and then raise an error' do
                    expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                    expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).exactly(3).times
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).exactly(3).times
                    expect(disk_manager).to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name).exactly(3).times
                    expect(azure_client).to receive(:delete_network_interface).twice

                    expect do
                      vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                      expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end

                context 'and an error occurs when deleting vm' do
                  before do
                    allow(azure_client).to receive(:delete_virtual_machine)
                      .and_raise('cannot delete the vm')
                  end

                  it 'should try to delete vm, then raise an error, but not delete the NICs' do
                    expect(azure_client).to receive(:create_virtual_machine).once
                    expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                    expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, os_disk_name)
                    expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                    expect(disk_manager).not_to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name)
                    expect(azure_client).not_to receive(:delete_network_interface)

                    expect do
                      vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/The VM fails in provisioning./)
                      expect(error.inspect).to match(/fake error message/)
                      expect(error.inspect).to match(/And an error is thrown in cleanuping VM, os disk or ephemeral disk before retry./)
                      expect(error.inspect).to match(/cannot delete the vm/)
                      # If the cleanup fails, then the VM resources have to be kept
                      expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end

                context 'and an error occurs when deleting vm for the first time but the vm is deleted successfully after retrying' do
                  before do
                    call_count = 0
                    allow(azure_client).to receive(:delete_virtual_machine) do
                      call_count += 1
                      call_count == 1 ? raise('cannot delete the vm') : true
                    end
                  end

                  it 'should delete vm and then raise an error' do
                    expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                    expect(azure_client).to receive(:delete_virtual_machine).exactly(4).times # Failed once and succeeded 3 times
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).exactly(3).times
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).exactly(3).times
                    expect(disk_manager).to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name).exactly(3).times
                    expect(azure_client).to receive(:delete_network_interface).twice

                    expect do
                      vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                      expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end
              end
            end

            context 'and use_managed_disks is true' do
              context 'and ephemeral_disk does not exist' do
                before do
                  allow(disk_manager2).to receive(:ephemeral_disk)
                    .and_return(nil)
                end

                it 'should delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, os_disk_name).exactly(3).times
                  expect(disk_manager2).not_to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, ephemeral_disk_name)
                  expect(azure_client).to receive(:delete_network_interface).twice

                  expect do
                    vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context 'and ephemeral_disk exists' do
                it 'should delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, os_disk_name).exactly(3).times
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, ephemeral_disk_name).exactly(3).times
                  expect(azure_client).to receive(:delete_network_interface).twice

                  expect do
                    vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end
            end
          end

          context 'and keep_failed_vms is true in global configuration' do
            let(:azure_config_to_keep_failed_vms) do
              mock_azure_config_merge(
                'keep_failed_vms' => true
              )
            end
            let(:vm_manager_to_keep_failed_vms) { Bosh::AzureCloud::VMManager.new(azure_config_to_keep_failed_vms, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }
            let(:azure_config_managed_to_keep_failed_vms) do
              mock_azure_config_merge(
                'use_managed_disks' => true,
                'keep_failed_vms' => true
              )
            end
            let(:vm_manager2_to_keep_failed_vms) { Bosh::AzureCloud::VMManager.new(azure_config_managed_to_keep_failed_vms, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }

            before do
              allow(vm_manager_to_keep_failed_vms).to receive(:_get_stemcell_info).and_return(stemcell_info)
              allow(vm_manager2_to_keep_failed_vms).to receive(:_get_stemcell_info).and_return(stemcell_info)
              allow(vm_manager_to_keep_failed_vms).to receive(:get_storage_account_from_vm_properties)
                .and_return(name: storage_account_name)
              allow(vm_manager2_to_keep_failed_vms).to receive(:get_storage_account_from_vm_properties)
                .and_return(name: storage_account_name)
            end

            context 'and use_managed_disks is false' do
              context 'and ephemeral_disk does not exist' do
                before do
                  allow(disk_manager).to receive(:ephemeral_disk)
                    .and_return(nil)
                end

                it 'should not delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).twice
                  expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).twice
                  expect(disk_manager).to receive(:delete_vm_status_files)
                    .with(storage_account_name, vm_name).twice
                  expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                  expect(azure_client).not_to receive(:delete_network_interface)

                  expect do
                    vm_manager_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context 'and ephemeral_disk exists' do
                context 'and all the vm resources are deleted successfully' do
                  it 'should not delete vm and then raise an error' do
                    expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                    expect(azure_client).to receive(:delete_virtual_machine).twice # CPI doesn't delete the VM for the last time
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).twice
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).twice
                    expect(disk_manager).to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name).twice
                    expect(azure_client).not_to receive(:delete_network_interface)

                    expect do
                      vm_manager_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                      expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end

                context 'and an error occurs when deleting vm' do
                  before do
                    allow(azure_client).to receive(:delete_virtual_machine)
                      .and_raise('cannot delete the vm')
                  end

                  it 'should not delete vm and then raise an error' do
                    expect(azure_client).to receive(:create_virtual_machine).once
                    expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times
                    expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, os_disk_name)
                    expect(disk_manager).not_to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
                    expect(disk_manager).not_to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name)
                    expect(azure_client).not_to receive(:delete_network_interface)

                    expect do
                      vm_manager_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/The VM fails in provisioning./)
                      expect(error.inspect).to match(/fake error message/)
                      expect(error.inspect).to match(/And an error is thrown in cleanuping VM, os disk or ephemeral disk before retry./)
                      expect(error.inspect).to match(/cannot delete the vm/)
                      # If the cleanup fails, then the VM resources have to be kept
                      expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end

                context 'and an error occurs when deleting vm for the first time but the vm is deleted successfully after retrying' do
                  before do
                    call_count = 0
                    allow(azure_client).to receive(:delete_virtual_machine) do
                      call_count += 1
                      call_count == 1 ? raise('cannot delete the vm') : true
                    end
                  end

                  it 'should not delete vm and then raise an error' do
                    expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                    expect(azure_client).to receive(:delete_virtual_machine).exactly(3).times # Failed once; succeeded 2 times; CPI should not delete the VM for the last time
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name).twice
                    expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name).twice
                    expect(disk_manager).to receive(:delete_vm_status_files)
                      .with(storage_account_name, vm_name).twice
                    expect(azure_client).not_to receive(:delete_network_interface)

                    expect do
                      vm_manager_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                    end.to raise_error { |error|
                      expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                      expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                    }
                  end
                end
              end
            end

            context 'and use_managed_disks is true' do
              context 'and ephemeral_disk does not exist' do
                before do
                  allow(disk_manager2).to receive(:ephemeral_disk)
                    .and_return(nil)
                end

                it 'should not delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).twice
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, os_disk_name).twice
                  expect(disk_manager2).not_to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, ephemeral_disk_name)
                  expect(azure_client).not_to receive(:delete_network_interface)

                  expect do
                    vm_manager2_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
                    expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                    expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                  }
                end
              end

              context 'and ephemeral_disk exists' do
                it 'should not delete vm and then raise an error' do
                  expect(azure_client).to receive(:create_virtual_machine).exactly(3).times
                  expect(azure_client).to receive(:delete_virtual_machine).twice
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, os_disk_name).twice
                  expect(disk_manager2).to receive(:delete_disk)
                    .with(MOCK_RESOURCE_GROUP_NAME, ephemeral_disk_name).twice
                  expect(azure_client).not_to receive(:delete_network_interface)

                  expect do
                    vm_manager2_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
                  end.to raise_error { |error|
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
end
