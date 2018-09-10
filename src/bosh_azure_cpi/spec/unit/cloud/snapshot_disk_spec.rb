# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#snapshot_disk' do
    let(:metadata) { {} }
    let(:snapshot_cid) { 'fake-snapshot-cid' }
    let(:snapshot_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:caching) { 'fake-cacing' }
    let(:disk_cid) { 'fake-disk-cid' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .with(disk_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(disk_id_object)

      allow(snapshot_id_object).to receive(:to_s)
        .and_return(snapshot_cid)

      allow(disk_id_object).to receive(:resource_group_name)
        .and_return(resource_group_name)
      allow(disk_id_object).to receive(:caching)
        .and_return(caching)

      allow(telemetry_manager).to receive(:monitor)
        .with('snapshot_disk', id: disk_cid).and_call_original
    end

    context 'when the disk is a managed disk' do
      context 'when the disk starts with bosh-disk-data' do
        let(:disk_name) { 'bosh-disk-data-fake-guid' }

        before do
          allow(disk_id_object).to receive(:disk_name)
            .and_return(disk_name)
        end

        it 'should take a managed snapshot of the disk' do
          expect(Bosh::AzureCloud::DiskId).to receive(:create)
            .with(caching, true, resource_group_name: resource_group_name)
            .and_return(snapshot_id_object)
          expect(disk_manager2).to receive(:snapshot_disk)
            .with(snapshot_id_object, disk_name, metadata)

          expect(cloud.snapshot_disk(disk_cid, metadata)).to eq(snapshot_cid)
        end
      end

      context 'when the disk NOT start with bosh-disk-data' do
        let(:disk_name) { 'fakestorageaccountname-fake-guid' }

        before do
          allow(disk_id_object).to receive(:disk_name)
            .and_return(disk_name)
          expect(disk_manager2).to receive(:get_data_disk)
            .with(disk_id_object)
            .and_return(name: disk_cid)
        end

        it 'should take a managed snapshot of the disk' do
          expect(Bosh::AzureCloud::DiskId).to receive(:create)
            .with(caching, true, resource_group_name: resource_group_name)
            .and_return(snapshot_id_object)
          expect(disk_manager2).to receive(:snapshot_disk)
            .with(snapshot_id_object, disk_name, metadata)

          expect(cloud.snapshot_disk(disk_cid, metadata)).to eq(snapshot_cid)
        end
      end
    end

    context 'when the disk is an unmanaged disk' do
      let(:storage_account_name) { 'fake-storage-account-name' }
      let(:disk_name) { 'fake-disk-name' }
      let(:snapshot_name) { 'fake-snapshot-name' }

      before do
        allow(disk_id_object).to receive(:disk_name)
          .and_return(disk_name)
        allow(disk_id_object).to receive(:storage_account_name)
          .and_return(storage_account_name)
        allow(disk_manager2).to receive(:get_data_disk)
          .with(disk_id_object)
          .and_return(nil)
      end

      it 'should take an unmanaged snapshot of the disk' do
        expect(disk_manager).to receive(:snapshot_disk)
          .with(storage_account_name, disk_name, metadata)
          .and_return(snapshot_name)
        expect(Bosh::AzureCloud::DiskId).to receive(:create)
          .with(caching, false, disk_name: snapshot_name, storage_account_name: storage_account_name)
          .and_return(snapshot_id_object)

        expect(cloud.snapshot_disk(disk_cid, metadata)).to eq(snapshot_cid)
      end
    end
  end
end
