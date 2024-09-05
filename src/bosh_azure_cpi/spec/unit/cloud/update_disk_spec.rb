# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#update_disk' do
    let(:disk_cid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:disk_name) { 'fake-disk-name' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:resource_group_name) { 'fake-resource-group-name' }

    let(:iops) { 500 }
    let(:mbps) { 100 }
    let(:storage_account) { 'fake-storage-account' }
    let(:cloud_properties) { { 'storage_account_type' => storage_account, 'iops' => iops, 'mbps' => mbps } }

    let(:old_disk_size_in_gib) { 512 }
    let(:new_disk_size_in_gib) { 1024 }
    let(:new_disk_size) { new_disk_size_in_gib * 1024 }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .and_return(disk_id_object)
      allow(disk_id_object).to receive(:resource_group_name)
        .and_return(resource_group_name)
      allow(disk_id_object).to receive(:disk_name)
        .and_return(disk_name)
      allow(disk_id_object).to receive(:caching)
        .and_return('None')
      allow(disk_manager2).to receive(:get_data_disk)
        .and_return({ disk_size: old_disk_size_in_gib }) # in GiB
      allow(disk_manager2).to receive(:update_disk)

      allow(telemetry_manager).to receive(:monitor)
        .with('update_disk', { id: disk_cid })
        .and_call_original
      allow(Bosh::Clouds::Config.logger).to receive(:info)
    end

    it 'updates the disk with the new size and cloud properties' do
      expect(disk_manager2).to receive(:update_disk)
        .with(disk_id_object, new_disk_size_in_gib, storage_account, iops, mbps)
      expect(Bosh::Clouds::Config.logger).to receive(:info)
        .with(/Finished update of disk 'fake-disk-name'/)

      expect do
        managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
      end.not_to raise_error
    end

    it 'raises an error if the disk is not found' do
      allow(disk_manager2).to receive(:get_data_disk).and_return(nil)

      expect do
        managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
      end.to raise_error(/Disk 'fake-disk-name' not found/)
    end

    context 'when the disk size are the same and cloud properties change' do
      let(:new_disk_size_in_gib) { old_disk_size_in_gib }

      it 'does not try to update the property' do
        expect(disk_manager2).to receive(:update_disk)

        expect do
          managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
        end.not_to raise_error
      end
    end

    context 'when the disk size are the same and cloud properties do not change' do
      let(:new_disk_size_in_gib) { old_disk_size_in_gib }
      let(:cloud_properties) { {} }

      it 'does not try to update the property' do
        expect(disk_manager2).not_to receive(:update_disk)

        expect do
          managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
        end.not_to raise_error
      end
    end

    context 'when the disk size is smaller' do
      let(:new_disk_size_in_gib) { 256 }

      it 'raises an error' do
        expect do
          managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
        end.to raise_error(/Disk size cannot be decreased/)
      end
    end

    context 'when caching settings changes' do
      let(:old_caching) { 'None' }
      let(:new_caching) { 'ReadWrite' }
      let(:cloud_properties) { { 'caching' => new_caching } }

      it 'raises an error' do
        allow(disk_manager2).to receive(:get_data_disk).and_return({ disk_size: old_disk_size_in_gib, caching: old_caching })

        expect do
          managed_cloud.update_disk(disk_cid, new_disk_size, cloud_properties)
        end.to raise_error(/Disk caching cannot be modified/)
      end
    end
  end
end
