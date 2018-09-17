# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#delete_snapshot' do
    let(:snapshot_cid) { 'fake-snapshot-cid' }
    let(:snapshot_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('delete_snapshot', id: snapshot_cid).and_call_original
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .with(snapshot_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(snapshot_id_object)
    end

    context 'when the snapshot is a managed snapshot' do
      let(:snapshot_name) { 'bosh-disk-data-fake-guid' }

      before do
        allow(snapshot_id_object).to receive(:disk_name)
          .and_return(snapshot_name)
      end

      it 'should delete the managed snapshot' do
        expect(disk_manager2).to receive(:delete_snapshot).with(snapshot_id_object)

        expect do
          cloud.delete_snapshot(snapshot_cid)
        end.not_to raise_error
      end
    end

    context 'when the snapshot is an unmanaged snapshot' do
      let(:snapshot_name) { 'fake-snapshot-name' }

      before do
        allow(snapshot_id_object).to receive(:disk_name)
          .and_return(snapshot_name)
      end

      it 'should delete the unmanaged snapshot' do
        expect(disk_manager).to receive(:delete_snapshot).with(snapshot_id_object)

        expect do
          cloud.delete_snapshot(snapshot_cid)
        end.not_to raise_error
      end
    end
  end
end
