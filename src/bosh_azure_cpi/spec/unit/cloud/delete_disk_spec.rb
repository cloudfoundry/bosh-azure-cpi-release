require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#delete_disk" do
    context "when use_managed_disks is true" do
      context "when the disk is a newly-created managed disk" do
        let(:disk_id) { "bosh-disk-data-guid" }

        it "should delete the managed disk" do
          expect(disk_manager2).to receive(:delete_disk).with(disk_id)
          expect {
            managed_cloud.delete_disk(disk_id)
          }.not_to raise_error
        end
      end

      context "when the disk is a managed disk which is created from a blob disk" do
        let(:disk_id) { "bosh-data-guid" }
        let(:disk) { double("disk") }

        before do
          allow(disk_manager2).to receive(:get_disk).with(disk_id).and_return(disk)
        end

        it "should delete the managed disk" do
          expect(disk_manager2).to receive(:delete_disk).with(disk_id)
          expect(disk_manager).not_to receive(:delete_disk)
          expect {
            managed_cloud.delete_disk(disk_id)
          }.not_to raise_error
        end
      end

      context "when the disk is an unmanaged disk" do
        let(:disk_id) { "bosh-data-guid" }

        before do
          allow(disk_manager2).to receive(:get_disk).with(disk_id).and_return(nil)
        end

        it "should delete the unmanaged disk" do
          expect(disk_manager2).not_to receive(:delete_disk)
          expect(disk_manager).to receive(:delete_disk).with(disk_id)
          expect {
            managed_cloud.delete_disk(disk_id)
          }.not_to raise_error
        end
      end

    end

    context "when use_managed_disks is false" do
      let(:disk_id) { "bosh-data-guid" }

      it "should delete the unmanaged disk" do
        expect(disk_manager).to receive(:delete_disk).with(disk_id)
        expect {
          cloud.delete_disk(disk_id)
        }.not_to raise_error
      end
    end
  end
end
