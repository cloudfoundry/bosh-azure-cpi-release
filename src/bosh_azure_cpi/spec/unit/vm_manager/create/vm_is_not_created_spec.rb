# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    let(:agent_util) { instance_double(Bosh::AzureCloud::BoshAgentUtil) }
    let(:network_spec) { {} }
    let(:config) { instance_double(Bosh::AzureCloud::Config) }

    before do
      allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
      allow(vm_manager2).to receive(:_get_stemcell_info).and_return(stemcell_info)
    end

    context 'when VM is not created' do
      context 'and azure_client.create_virtual_machine raises an AzureAsynchronousError' do
        context 'and AzureAsynchronousError.status is Failed' do
          before do
            allow(azure_client).to receive(:create_virtual_machine)
              .and_raise(Bosh::AzureCloud::AzureAsynchronousError.new('Failed'), 'fake error message')
          end

          context 'and keep_failed_vms is false in global configuration' do
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
                  vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                end.to(raise_error do |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                end)
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
                  vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                end.to(raise_error do |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).not_to match(/This VM fails in provisioning after multiple retries/)
                end)
              end
            end
          end

          context 'and keep_failed_vms is true in global configuration' do
            let(:azure_config_managed_to_keep_failed_vms) do
              mock_azure_config_merge(
                'keep_failed_vms' => true
              )
            end
            let(:vm_manager2_to_keep_failed_vms) { Bosh::AzureCloud::VMManager.new(azure_config_managed_to_keep_failed_vms, disk_manager2, azure_client, storage_account_manager, stemcell_manager2, light_stemcell_manager) }

            before do
              allow(vm_manager2_to_keep_failed_vms).to receive(:_get_stemcell_info).and_return(stemcell_info)
              allow(vm_manager2_to_keep_failed_vms).to receive(:get_storage_account_from_vm_properties)
                .and_return(name: storage_account_name)
            end

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
                  vm_manager2_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                end.to(raise_error do |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                end)
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
                  vm_manager2_to_keep_failed_vms.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                end.to(raise_error do |error|
                  expect(error.inspect).to match(/Bosh::AzureCloud::AzureAsynchronousError/)
                  expect(error.inspect).to match(/This VM fails in provisioning after multiple retries/)
                end)
              end
            end
          end
        end
      end
    end
  end
end
