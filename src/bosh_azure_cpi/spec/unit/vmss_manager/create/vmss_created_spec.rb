# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#create' do
    context 'when vmss not exists' do
      it 'should not raise error' do
        allow(stemcell_info).to receive(:os_type)
          .and_return('linux')
        allow(azure_client).to receive(:get_vmss_by_name)
          .and_return(nil)
        expect(azure_client).to receive(:create_vmss)
        allow(azure_client).to receive(:get_vmss_instances)
          .and_return(
            [
              {
                instanceId: '0',
                name: "#{vmss_name}_0"
              }
            ]
          )
        allow(vmss_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
        allow(config_disk_manager).to receive(:prepare_config_disk)
          .and_return(config_disk_obj)
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .and_return(config_disk_resource)
        expect(azure_client).to receive(:attach_disk_to_vmss_instance)
        expect do
          vmss_manager.create(bosh_vm_meta, location, vm_props, network_configurator, env_with_group)
        end.not_to raise_error
      end
    end

    context 'when vmss exists' do
      it 'should not raise error' do
        allow(stemcell_info).to receive(:os_type)
          .and_return('linux')
        allow(azure_client).to receive(:get_vmss_by_name)
          .and_return({})
        allow(azure_client).to receive(:scale_vmss_up)
        allow(azure_client).to receive(:get_vmss_instances)
          .and_return(
            [
              {
                instanceId: '0',
                name: "#{vmss_name}_0"
              }
            ],
            [
              {
                instanceId: '1',
                name: "#{vmss_name}_1"
              }
            ]
          )
        allow(vmss_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
        allow(config_disk_manager).to receive(:prepare_config_disk)
          .and_return(config_disk_obj)
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .and_return(config_disk_resource)
        expect(azure_client).to receive(:attach_disk_to_vmss_instance)
        expect do
          vmss_manager.create(bosh_vm_meta, location, vm_props, network_configurator, env_with_long_name_group)
        end.not_to raise_error
      end
    end
  end
end
