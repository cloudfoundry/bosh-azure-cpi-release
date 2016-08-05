require 'spec_helper'

describe Bosh::AzureCloud::DiskManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { Bosh::AzureCloud::DiskManager.new(azure_properties, blob_manager) }

  let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
  let(:disk_container) { "bosh" }
  let(:data_disk_prefix) { "bosh-data" }
  let(:disk_name) { "#{data_disk_prefix}-#{storage_account_name}-#{SecureRandom.uuid}-None" }

  describe "#prepare" do
    context "when the container exists" do
      before do
        allow(blob_manager).to receive(:has_container?).
          and_return(true)
      end

      it "does not create the container" do
        expect(blob_manager).not_to receive(:create_container)

        disk_manager.prepare(storage_account_name)
      end
    end

    context "when the container does not exist" do
      before do
        allow(blob_manager).to receive(:has_container?).
          and_return(false)
      end

      it "create the container" do
        expect(blob_manager).to receive(:create_container).
          with(storage_account_name, disk_container)

        disk_manager.prepare(storage_account_name)
      end
    end
  end

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

      it "should raise an error" do
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

    context "when caching is nil" do
      let(:cloud_properties) { {'caching' => nil} }

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

      it "should return true" do
        expect(disk_manager.has_disk?(disk_name)).to be(true)
      end
    end

    context "when the disk does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return(nil)
      end

      it "should return false" do
        expect(disk_manager.has_disk?(disk_name)).to be(false)
      end
    end
  end

  describe "#get_data_disk_caching" do
    it "returns the right caching" do
      expect(disk_manager.get_data_disk_caching(disk_name)).to eq("None")
    end
  end

  describe "#os_disk" do
    let(:disk_name) { 'fake-disk-name' }
    let(:disk_uri) { 'fake-disk-uri' }
    let(:instance_id) { 'fake-instance-id' }

    before do
      allow(disk_manager).to receive(:generate_os_disk_name).
        and_return(disk_name)
      allow(disk_manager).to receive(:get_disk_uri).
        and_return(disk_uri)
    end

    context "without root_disk nor caching" do
      let(:resource_pool) {
        {
          'instance_type' => 'STANDARD_A1'
        }
      }

      it "should return correct values" do
        disk_manager.resource_pool = resource_pool

        expect(
          disk_manager.os_disk(instance_id)
        ).to eq(
          {
            :disk_name    => disk_name,
            :disk_uri     => disk_uri,
            :disk_size    => nil,
            :disk_caching => 'ReadWrite'
          }
        )
      end
    end

    context "with caching" do
      context "when caching is valid" do
        let(:disk_caching) { 'ReadOnly' }
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1',
            'caching' => disk_caching
          }
        }

        it "should return correct values" do
          disk_manager.resource_pool = resource_pool

          expect(
            disk_manager.os_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
              :disk_uri     => disk_uri,
              :disk_size    => nil,
              :disk_caching => disk_caching
            }
          )
        end
      end

      context "when caching is invalid" do
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1',
            'caching' => 'invalid'
          }
        }

        it "should raise an error" do
          disk_manager.resource_pool = resource_pool

          expect {
            disk_manager.os_disk(instance_id)
          }.to raise_error /Unknown disk caching/
        end
      end
    end

    context "with root_disk" do
      context "without size" do
        context "with the ephemeral disk" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {}
            }
          }

          it "should return correct values" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.os_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => nil,
                :disk_caching => 'ReadWrite'
              }
            )
          end
        end

        context "without the ephemeral disk" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {},
              'ephemeral_disk' => {
                'use_root_disk' => true
              }
            }
          }

          it "should return correct values" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.os_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 30,
                :disk_caching => 'ReadWrite'
              }
            )
          end
        end
      end

      context "with a valid size" do
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1',
            'root_disk' => {
              'size' => 3 * 1024
            }
          }
        }

        it "should return correct values" do
          disk_manager.resource_pool = resource_pool

          expect(
            disk_manager.os_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
              :disk_uri     => disk_uri,
              :disk_size    => 3,
              :disk_caching => 'ReadWrite'
            }
          )
        end
      end

      context "with an invalid size" do
        context "When the size is smaller than 3 GiB" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 2 * 1024
              }
            }
          }

          it "should raise an error" do
            disk_manager.resource_pool = resource_pool

            expect {
              disk_manager.os_disk(instance_id)
            }.to raise_error /root_disk.size must not be smaller than 3 GiB/
          end
        end

        context "When the size is not an integer" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 'invalid-size'
              }
            }
          }

          it "should raise an error" do
            disk_manager.resource_pool = resource_pool

            expect {
              disk_manager.os_disk(instance_id)
            }.to raise_error
          end
        end
      end
    end
  end

  describe "#ephemeral_disk" do
    let(:disk_name) { 'ephemeral-disk' }
    let(:disk_uri) { 'fake-disk-uri' }
    let(:instance_id) { 'fake-instance-id' }

    before do
      allow(disk_manager).to receive(:get_disk_uri).
        and_return(disk_uri)
    end

    context "without ephemeral_disk" do
      context "with a valid instance_type" do
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1'
          }
        }

        it "should return correct values" do
          disk_manager.resource_pool = resource_pool

          expect(
            disk_manager.ephemeral_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
              :disk_uri     => disk_uri,
              :disk_size    => 70,
              :disk_caching => 'ReadWrite'
            }
          )
        end
      end

      context "with an invalid instance_type" do
        let(:resource_pool) {
          {
            'instance_type' => 'invalid-instance-type'
          }
        }

        it "should return correct values" do
          disk_manager.resource_pool = resource_pool

          expect(
            disk_manager.ephemeral_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
              :disk_uri     => disk_uri,
              :disk_size    => 30,
              :disk_caching => 'ReadWrite'
            }
          )
        end
      end
    end

    context "with ephemeral_disk" do
      context "with use_root_disk" do
        context "when use_root_disk is false" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {
                'use_root_disk' => false
              }
            }
          }

          it "should return correct values" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.ephemeral_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 70,
                :disk_caching => 'ReadWrite'
              }
            )
          end
        end

        context "when use_root_disk is true" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {
                'use_root_disk' => true
              }
            }
          }

          it "should return correct values" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.ephemeral_disk(instance_id)
            ).to be_nil
          end
        end
      end

      context "without use_root_disk" do
        context "without size" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {}
            }
          }

          it "should return correct values" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.ephemeral_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 70,
                :disk_caching => 'ReadWrite'
              }
            )
          end
        end

        context "with size" do
          context "when the size is valid" do
            let(:resource_pool) {
              {
                'instance_type' => 'STANDARD_A1',
                'ephemeral_disk' => {
                  'size' => 30 * 1024
                }
              }
            }
            
          end

          context "when the size is not an integer" do
            let(:resource_pool) {
              {
                'instance_type' => 'STANDARD_A1',
                'ephemeral_disk' => {
                  'size' => 'invalid-size'
                }
              }
            }

            it "should raise an error" do
              disk_manager.resource_pool = resource_pool

              expect {
                disk_manager.ephemeral_disk(instance_id)
              }.to raise_error
            end
          end
        end
      end
    end
  end
end
