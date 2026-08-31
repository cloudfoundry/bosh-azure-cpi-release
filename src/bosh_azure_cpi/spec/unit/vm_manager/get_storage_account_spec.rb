# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe '#get_storage_account_from_vm_properties' do
    let(:props_factory) { Bosh::AzureCloud::PropsFactory.new(Bosh::AzureCloud::ConfigFactory.build(mock_cloud_options['properties'])) }
    let(:azure_config) { mock_azure_config }
    let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_config, blob_manager, azure_client) }
    let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
    let(:stemcell_manager2) { instance_double(Bosh::AzureCloud::StemcellManager2) }
    let(:light_stemcell_manager) { instance_double(Bosh::AzureCloud::LightStemcellManager) }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_config, disk_manager2, azure_client, storage_account_manager, stemcell_manager2, light_stemcell_manager) }
    let(:location) { 'fake-location' }
    let(:default_storage_account) do
      {
        name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    end

    before do
      allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    let(:storage_account_name) { 'fake-storage-account-name-in-resource-pool' }
    let(:storage_account) do
      {
        name: storage_account_name
      }
    end

    context 'when vm_properties does not contain storage_account_name' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'fake-vm-size'
        )
      end

      it 'should return the default storage account' do
        expect(
          vm_manager.get_storage_account_from_vm_properties(vm_props, location)
        ).to be(default_storage_account)
      end
    end

    context 'when vm_properties contains storage_account_name' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'fake-vm-size',
          'storage_account_name' => storage_account_name,
          'storage_account_type' => 'fake-storage_account_type',
          'storage_account_kind' => 'StorageV2'
        )
      end

      it 'should try to get or create the storage account' do
        expect(storage_account_manager).to receive(:get_or_create_storage_account)
          .with(storage_account_name, {}, 'fake-storage_account_type', 'StorageV2', location, %w[bosh stemcell], false)
          .and_return(storage_account)
        expect(
          vm_manager.get_storage_account_from_vm_properties(vm_props, location)
        ).to be(storage_account)
      end
    end
  end
end
