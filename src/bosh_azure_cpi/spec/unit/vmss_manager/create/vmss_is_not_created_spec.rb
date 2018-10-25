# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#create' do
    context 'when bosh group not exists' do
      it 'should raise error' do
        expect do
          vmss_manager.create(bosh_vm_meta, vm_props, network_configurator, empty_env)
        end.to raise_error(Bosh::Clouds::VMCreationFailed, /Instance not created./)
      end
    end

    context 'when attach disk failed' do
      context 'when keep failed vm disabled' do
        it 'should remove the instance created' do
        end
      end
      context 'when keep failed vm enabled' do
        it 'should not remove the instance created' do
          allow(stemcell_info).to receive(:os_type)
            .and_return('linux')
          allow(azure_client).to receive(:get_vmss_by_name)
            .and_return({})
          allow(azure_client).to receive(:update_vmss_sku)
          allow(azure_client).to receive(:get_vmss_instances)
            .and_return(
              [
                {
                  instanceId: '0',
                  name: "#{vmss_name}_0",
                  zones: ['1']
                }
              ],
              [
                {
                  instanceId: '1',
                  name: "#{vmss_name}_1",
                  zones: ['2']
                }
              ]
            )
          allow(vmss_manager_to_keep_failed_vms).to receive(:_get_stemcell_info).and_return(stemcell_info)
          allow(config_disk_manager).to receive(:prepare_config_disk)
            .and_return(config_disk_obj)
          allow(azure_client).to receive(:get_managed_disk_by_name)
            .and_return(config_disk_resource)
          expect(azure_client).to receive(:attach_disk_to_vmss_instance)
            .and_raise 'failed to attach disk'
          expect do
            vmss_manager_to_keep_failed_vms.create(bosh_vm_meta, vm_props, network_configurator, env_with_long_name_group)
          end.to raise_error(Bosh::Clouds::VMCreationFailed, /New instance in VMSS created, but probably config disk failed to attach./)
        end
      end
    end
  end
end
