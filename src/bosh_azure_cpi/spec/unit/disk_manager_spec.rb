require 'spec_helper'

describe Bosh::AzureCloud::DiskManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { Bosh::AzureCloud::DiskManager.new(azure_properties, blob_manager) }

  let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
  let(:disk_container) { "bosh" }
  let(:data_disk_prefix) { "bosh-data" }
  let(:disk_name) { "#{data_disk_prefix}-#{storage_account_name}-#{SecureRandom.uuid}-None" }

  describe "#delete_disk" do
    context "when the disk exists" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return({})
      end

      it "deletes the disk" do
        expect(blob_manager).to receive(:delete_blob).
          with(storage_account_name, disk_container, "#{disk_name}.vhd")

        disk_manager.delete_disk(disk_name)
      end
    end

    context "when the disk does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return(nil)
      end
      it "does not delete the disk" do
        expect(blob_manager).not_to receive(:delete_blob)

        disk_manager.delete_disk(disk_name)
      end
    end
  end  

  describe "#delete_vm_status_files" do
    it "deletes vm status files" do
      allow(blob_manager).to receive(:list_blobs).
        and_return([
          double("blob", :name => "a.status"),
          double("blob", :name => "b.status"),
          double("blob", :name => "a.vhd"),
          double("blob", :name => "b.vhd")
        ])
      expect(blob_manager).to receive(:delete_blob).
        with(storage_account_name, "bosh", "a.status")
      expect(blob_manager).to receive(:delete_blob).
        with(storage_account_name, "bosh", "b.status")

      disk_manager.delete_vm_status_files(storage_account_name, "")
    end
  end  

  describe "#snapshot_disk" do
    let(:metadata) { {} }
    let(:snapshot_time) { "fake-snapshot-time" }

    it "returns the snapshot disk name" do
      allow(blob_manager).to receive(:snapshot_blob).
        with(storage_account_name, disk_container, "#{disk_name}.vhd", metadata).
        and_return(snapshot_time)

      snapshot_id = disk_manager.snapshot_disk(disk_name, metadata)
      expect(snapshot_id).to include(disk_name)
      expect(snapshot_id).to include(snapshot_time)
    end
  end  

  describe "#delete_snapshot" do
    let(:snapshot_time) { "fake-snapshot-time" }
    let(:snapshot_id) { "#{disk_name}--#{snapshot_time}" }

    it "deletes the snapshot" do
      expect(blob_manager).to receive(:delete_blob_snapshot).
        with(storage_account_name, disk_container, "#{disk_name}.vhd", snapshot_time)

      disk_manager.delete_snapshot(snapshot_id)
    end
  end  

  describe "#create_disk" do
    let(:size) { 100 }

    context "when caching is invalid" do
      let(:cloud_properties) { {'caching' => 'Invalid'} }

      it "raises an error" do
        allow(blob_manager).to receive(:create_empty_vhd_blob)

        expect{
          disk_manager.create_disk(storage_account_name, size, cloud_properties)
        }.to raise_error /Unknown disk caching/
      end
    end

    context "when caching is not specified" do
      let(:cloud_properties) { {} }

      it "returns the disk name with default caching" do
        allow(blob_manager).to receive(:create_empty_vhd_blob)

        disk_name = disk_manager.create_disk(storage_account_name, size, cloud_properties)
        expect(disk_name).to include(storage_account_name)
        expect(disk_name).to include("None")
      end
    end

    context "when caching is specified" do
      let(:cloud_properties) { {'caching' => 'ReadOnly'} }

      it "returns the disk name with the specified caching" do
        allow(blob_manager).to receive(:create_empty_vhd_blob)

        disk_name = disk_manager.create_disk(storage_account_name, size, cloud_properties)
        expect(disk_name).to include(storage_account_name)
        expect(disk_name).to include("ReadOnly")
      end
    end
  end  

  describe "#has_disk?" do
    context "when the disk exists" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return({})
      end

      it "returns true" do
        expect(disk_manager.has_disk?(disk_name)).to be(true)
      end
    end

    context "when the disk does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return(nil)
      end

      it "returns false" do
        expect(disk_manager.has_disk?(disk_name)).to be(false)
      end
    end
  end

  describe "#get_data_disk_caching" do
    it "returns the right caching" do
      expect(disk_manager.get_data_disk_caching(disk_name)).to eq("None")
    end
  end
end
