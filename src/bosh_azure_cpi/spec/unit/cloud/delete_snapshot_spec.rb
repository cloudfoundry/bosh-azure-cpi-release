require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#delete_snapshot" do
    context "when the snapshot is a managed snapshot" do
      let(:snapshot_id) { 'bosh-disk-data-fake-guid' }

      it 'should delete the managed snapshot' do
        expect(disk_manager2).to receive(:delete_snapshot).with(snapshot_id)

        expect {
          cloud.delete_snapshot(snapshot_id)
        }.not_to raise_error
      end
    end

    context "when the snapshot is an unmanaged snapshot" do
      let(:snapshot_id) { 'fake-snapshot-id' }

      it 'should delete the unmanaged snapshot' do
        expect(disk_manager).to receive(:delete_snapshot).with(snapshot_id)

        expect {
          cloud.delete_snapshot(snapshot_id)
        }.not_to raise_error
      end
    end
  end
end
