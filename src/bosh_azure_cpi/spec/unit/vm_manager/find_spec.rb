# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe '#find' do
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
    let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
    let(:azure_config) { mock_azure_config }
    let(:stemcell_manager) { instance_double(Bosh::AzureCloud::StemcellManager) }
    let(:stemcell_manager2) { instance_double(Bosh::AzureCloud::StemcellManager2) }
    let(:light_stemcell_manager) { instance_double(Bosh::AzureCloud::LightStemcellManager) }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_config, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }

    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }

    let(:vm_name) { 'fake-vm-name' }
    let(:resource_group_name) { 'fake-resource-group-name' }

    before do
      allow(instance_id).to receive(:resource_group_name)
        .and_return(resource_group_name)
      allow(instance_id).to receive(:vm_name)
        .and_return(vm_name)
    end

    context 'when everything is ok' do
      it 'finds the instance by id' do
        expect(azure_client).to receive(:get_virtual_machine_by_name)
          .with(resource_group_name, vm_name)
        expect do
          vm_manager.find(instance_id)
        end.not_to raise_error
      end
    end
  end
end
