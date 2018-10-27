# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#delete' do
    context 'when everything ok' do
      let(:vmss_instance) do
        {}
      end
      it 'should not raise error' do
        expect(azure_client).to receive(:get_vmss_instance)
          .and_return(vmss_instance)
        expect(azure_client).to receive(:delete_vmss_instance)
        expect do
          vmss_manager.delete(instance_id_vmss)
        end.not_to raise_error
      end
    end

    context 'when there is config disk attached' do
      let(:fake_cfg_disk_name) { 'bosh-cfg-disk-fake_disk' }
      let(:vmss_instance) do
        {
          data_disks: [
            {
              name: fake_cfg_disk_name,
              managed_disk: {
                id: "/subscriptions/fake_sub_id/resourceGroups/fake_resource_group/providers/Microsoft.Compute/disks/#{fake_cfg_disk_name}"
              }
            }
          ]
        }
      end
      it 'should not raise error' do
        expect(azure_client).to receive(:get_vmss_instance)
          .and_return(vmss_instance)
        expect(azure_client).to receive(:delete_vmss_instance)
        expect(disk_manager2).to receive(:delete_disk)
        expect do
          vmss_manager.delete(instance_id_vmss)
        end.not_to raise_error
      end
    end
  end
end
