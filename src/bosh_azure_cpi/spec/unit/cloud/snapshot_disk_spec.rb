require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#snapshot_disk" do
    let(:metadata) { {} }
    let(:snapshot_id) { 'fake-snapshot-id' }

    context "when the disk is a managed disk" do
      context "when the disk starts with bosh-disk-data" do
        let(:disk_id) { "bosh-disk-data-fake-guid" }

        it 'should take a managed snapshot of the disk' do
          expect(disk_manager2).to receive(:snapshot_disk).
            with(disk_id, metadata).
            and_return(snapshot_id)

          expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
        end
      end

      context "when the disk starts with bosh-disk-data" do
        let(:disk_id) { "fakestorageaccountname-fake-guid" }

        before do
          expect(disk_manager2).to receive(:get_disk).
            with(disk_id).
            and_return({:name=>disk_id})
        end

        it 'should take a managed snapshot of the disk' do
          expect(disk_manager2).to receive(:snapshot_disk).
            with(disk_id, metadata).
            and_return(snapshot_id)

          expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
        end
      end
    end

    context "when the disk is an unmanaged disk" do
      let(:disk_id) { "fakestorageaccountname-fake-guid" }

      before do
        expect(disk_manager2).to receive(:get_disk).
          with(disk_id).
          and_return(nil)
      end

      it 'should take an unmanaged snapshot of the disk' do
        expect(disk_manager).to receive(:snapshot_disk).
          with(disk_id, metadata).
          and_return(snapshot_id)

        expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
      end
    end
  end
end
