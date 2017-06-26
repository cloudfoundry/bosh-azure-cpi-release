require 'spec_helper'

describe Bosh::AzureCloud::DiskManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { Bosh::AzureCloud::DiskManager.new(azure_properties, blob_manager) }

  let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
  let(:disk_container) { "bosh" }
  let(:os_disk_prefix) { "bosh-os" }
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

        expect {
          disk_manager.delete_disk(disk_name)
        }.not_to raise_error
      end
    end

    context "when the disk does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return(nil)
      end

      it "does not delete the disk" do
        expect(blob_manager).not_to receive(:delete_blob)

        expect {
          disk_manager.delete_disk(disk_name)
        }.not_to raise_error
      end
    end
  end  

  describe "#delete_vm_status_files" do
    context "when there are several vm status file" do
      before do
        allow(blob_manager).to receive(:list_blobs).
          and_return([
            double("blob", :name => "a.status"),
            double("blob", :name => "b.status"),
            double("blob", :name => "a.vhd"),
            double("blob", :name => "b.vhd")
          ])
      end

      it "deletes vm status files" do
        expect(blob_manager).to receive(:delete_blob).
          with(storage_account_name, "bosh", "a.status")
        expect(blob_manager).to receive(:delete_blob).
          with(storage_account_name, "bosh", "b.status")

        expect {
          disk_manager.delete_vm_status_files(storage_account_name, "")
        }.not_to raise_error
      end
    end

    context "when there are no vm status file" do
      before do
        allow(blob_manager).to receive(:list_blobs).
          and_return([])
      end

      it "doesn't delete vm status files" do
        expect(blob_manager).not_to receive(:delete_blob)

        expect {
          disk_manager.delete_vm_status_files(storage_account_name, "")
        }.not_to raise_error
      end
    end

    context "when an exception is raised when deleting the files" do
      before do
        allow(blob_manager).to receive(:list_blobs).
          and_return([
            double("blob", :name => "a.status"),
            double("blob", :name => "b.status"),
            double("blob", :name => "a.vhd"),
            double("blob", :name => "b.vhd")
          ])
        allow(blob_manager).to receive(:delete_blob).and_raise(StandardError)
      end

      it "ignores the exception and doesn't raise error" do
        expect {
          disk_manager.delete_vm_status_files(storage_account_name, "")
        }.not_to raise_error
      end
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

      expect {
        disk_manager.delete_snapshot(snapshot_id)
      }.not_to raise_error
    end
  end  

  describe "#create_disk" do
    let(:size) { 100 }
    let(:caching) { 'ReadOnly' }

    it "returns the disk name with the specified caching" do
      allow(blob_manager).to receive(:create_empty_vhd_blob)

      disk_name = disk_manager.create_disk(size, storage_account_name, caching)
      expect(disk_name).to include(storage_account_name)
      expect(disk_name).to include(caching)
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

  describe "#is_migrated?" do
    context "when the disk does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return(nil)
      end

      it "should return false" do
        expect(disk_manager.is_migrated?(disk_name)).to be(false)
      end
    end

    context "when the disk exists" do
      before do
        allow(blob_manager).to receive(:get_blob_properties).
          and_return({})
      end

      context "when the disk has the metadata" do
        let(:metadata) {
          {
            "user_agent" => "bosh",
            "migrated" => "true"
          }
        }
        before do
          allow(blob_manager).to receive(:get_blob_metadata).
            and_return(metadata)
        end

        it "should return true" do
          expect(disk_manager.is_migrated?(disk_name)).to be(true)
        end
      end

      context "when the disk doesn't have the metadata" do
        let(:metadata) { {} }
        before do
          allow(blob_manager).to receive(:get_blob_metadata).
            and_return(metadata)
        end

        it "should return false" do
          expect(disk_manager.is_migrated?(disk_name)).to be(false)
        end
      end
    end
  end

  describe "#get_disk_uri" do
    context "when the disk name is invalid" do
      let(:disk_name) { "invalid-disk-name" }

      it "raises an error" do
        expect {
          disk_manager.get_disk_uri(disk_name)
        }.to raise_error /Invalid disk name #{disk_name}/
      end
    end

    context "when the disk is a data disk" do
      it "returns the right disk uri" do
        expect(blob_manager).to receive(:get_blob_uri).
          with(storage_account_name, disk_container, "#{disk_name}.vhd").
          and_return("fake-uri")
        expect(disk_manager.get_disk_uri(disk_name)).to eq("fake-uri")
      end
    end

    context "when the disk is an OS disk" do
      let(:disk_name) { "bosh-os-#{storage_account_name}-#{SecureRandom.uuid}-None" }

      it "returns the right disk uri" do
        expect(blob_manager).to receive(:get_blob_uri).
          with(storage_account_name, disk_container, "#{disk_name}.vhd").
          and_return("fake-uri")
        expect(disk_manager.get_disk_uri(disk_name)).to eq("fake-uri")
      end
    end
  end

  describe "#get_data_disk_caching" do
    it "returns the right caching" do
      expect(disk_manager.get_data_disk_caching(disk_name)).to eq("None")
    end
  end

  describe "#get_disk_size_in_gb" do
    let(:disk_size) { 42 * 1024 * 1024 * 1024 }

    before do
      expect(blob_manager).to receive(:get_blob_size_in_bytes).
        with(storage_account_name, disk_container, "#{disk_name}.vhd").
        and_return(disk_size)
    end

    it "returns the disk size" do
      expect(disk_manager.get_disk_size_in_gb(disk_name)).to eq(42)
    end
  end

  describe "#generate_os_disk_name" do
    let(:instance_id) { "fake-instance-id" }

    it "returns the right os disk name" do
      expect(disk_manager.generate_os_disk_name(instance_id)).to eq("#{os_disk_prefix}-fake-instance-id")
    end
  end

  describe "#generate_ephemeral_disk_name" do
    let(:instance_id) { "fake-instance-id" }

    it "returns the right ephemeral disk name" do
      expect(disk_manager.generate_ephemeral_disk_name(instance_id)).to eq("#{os_disk_prefix}-fake-instance-id-ephemeral-disk")
    end
  end

  describe "#os_disk" do
    let(:disk_name) { 'fake-disk-name' }
    let(:disk_uri) { 'fake-disk-uri' }
    let(:instance_id) { 'fake-instance-id' }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }
    let(:minimum_disk_size) { 3 * 1024 }

    before do
      allow(disk_manager).to receive(:generate_os_disk_name).
        and_return(disk_name)
      allow(disk_manager).to receive(:get_disk_uri).
        and_return(disk_uri)
      allow(stemcell_info).to receive(:disk_size).
        and_return(minimum_disk_size)
      allow(stemcell_info).to receive(:is_windows?).
        and_return(false)
    end

    # Caching
    context "when caching is not specified" do
      let(:resource_pool) {
        {
          'instance_type' => 'STANDARD_A1'
        }
      }

      it "should return the default caching for os disk: ReadWrite" do
        disk_manager.resource_pool = resource_pool

        expect(
          disk_manager.os_disk(instance_id, stemcell_info)
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

    context "when caching is specified" do
      context "when caching is valid" do
        let(:disk_caching) { 'ReadOnly' }
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1',
            'caching' => disk_caching
          }
        }

        it "should return the specified caching" do
          disk_manager.resource_pool = resource_pool

          expect(
            disk_manager.os_disk(instance_id, stemcell_info)
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
            disk_manager.os_disk(instance_id, stemcell_info)
          }.to raise_error /Unknown disk caching/
        end
      end
    end

    # Disk Size
    context "without root_disk" do
      let(:resource_pool) {
        {
          'instance_type' => 'STANDARD_A1'
        }
      }

      it "should return disk_size: nil" do
        disk_manager.resource_pool = resource_pool

        expect(
          disk_manager.os_disk(instance_id, stemcell_info)
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

    context "with root_disk" do
      context "when size is not specified" do
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
              disk_manager.os_disk(instance_id, stemcell_info)
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

          context "when the OS is Linux" do
            context "when the minimum_disk_size is smaller than 30 GiB" do
              let(:minimum_disk_size) { 3 * 1024 }
              before do
                allow(stemcell_info).to receive(:disk_size).
                  and_return(minimum_disk_size)
              end

              it "should return 30 GiB as the disk size" do
                disk_manager.resource_pool = resource_pool

                expect(
                  disk_manager.os_disk(instance_id, stemcell_info)
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

            context "when the minimum_disk_size is larger than 30 GiB" do
              let(:minimum_disk_size) { 50 * 1024 }
              before do
                allow(stemcell_info).to receive(:disk_size).
                  and_return(minimum_disk_size)
              end

              it "should return minimum_disk_size as the disk size" do
                disk_manager.resource_pool = resource_pool

                expect(
                  disk_manager.os_disk(instance_id, stemcell_info)
                ).to eq(
                  {
                    :disk_name    => disk_name,
                    :disk_uri     => disk_uri,
                    :disk_size    => minimum_disk_size / 1024,
                    :disk_caching => 'ReadWrite'
                  }
                )
              end
            end
          end

          context "when the OS is Windows" do
            before do
              allow(stemcell_info).to receive(:is_windows?).
                and_return(true)
            end
            context "when the minimum_disk_size is smaller than 128 GiB" do
              let(:minimum_disk_size) { (128 - 1)* 1024 }
              before do
                allow(stemcell_info).to receive(:disk_size).
                  and_return(minimum_disk_size)
              end

              it "should return 128 GiB as the disk size" do
                disk_manager.resource_pool = resource_pool

                expect(
                  disk_manager.os_disk(instance_id, stemcell_info)
                ).to eq(
                  {
                    :disk_name    => disk_name,
                    :disk_uri     => disk_uri,
                    :disk_size    => 128,
                    :disk_caching => 'ReadWrite'
                  }
                )
              end
            end

            context "when the minimum_disk_size is larger than 128 GiB" do
              let(:minimum_disk_size) { (128 + 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:disk_size).
                  and_return(minimum_disk_size)
              end

              it "should return minimum_disk_size as the disk size" do
                disk_manager.resource_pool = resource_pool

                expect(
                  disk_manager.os_disk(instance_id, stemcell_info)
                ).to eq(
                  {
                    :disk_name    => disk_name,
                    :disk_uri     => disk_uri,
                    :disk_size    => minimum_disk_size / 1024,
                    :disk_caching => 'ReadWrite'
                  }
                )
              end
            end
          end
        end
      end

      context "when size is specified" do
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
              disk_manager.os_disk(instance_id, stemcell_info)
            }.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is `invalid-size'."
          end
        end

        context "When the size is smaller than minimum_disk_size" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 2 * 1024
              }
            }
          }
          let(:minimum_disk_size) { 4 * 1024 }
          before do
            allow(stemcell_info).to receive(:disk_size).
              and_return(minimum_disk_size)
          end

          it "should use the minimum_disk_size" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.os_disk(instance_id, stemcell_info)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 4,
                :disk_caching => 'ReadWrite'
              }
            )
          end
        end

        context "When the size is divisible by 1024" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 5 * 1024
              }
            }
          }

          it "should return the correct disk_size" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.os_disk(instance_id, stemcell_info)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 5,
                :disk_caching => 'ReadWrite'
              }
           )
          end
        end
        context "When the size is not divisible by 1024" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 5 * 1024 + 512
              }
            }
          }

          it "should return the smallest Integer greater than or equal to size/1024 for disk_size" do
            disk_manager.resource_pool = resource_pool

            expect(
              disk_manager.os_disk(instance_id, stemcell_info)
            ).to eq(
              {
                :disk_name    => disk_name,
                :disk_uri     => disk_uri,
                :disk_size    => 6,
                :disk_caching => 'ReadWrite'
              }
           )
          end
        end
      end
    end
  end

  describe "#ephemeral_disk" do
    let(:disk_name) { 'ephemeral-disk' }
    let(:disk_uri) { 'fake-disk-uri' }
    let(:instance_id) { 'fake-instance-id' }
    let(:default_ephemeral_disk_size) { 70 } # The default value is default_ephemeral_disk_size for Standard_A1 

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
              :disk_size    => default_ephemeral_disk_size,
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

        it "should return 30 as the default disk size" do
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
                :disk_size    => default_ephemeral_disk_size,
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
                :disk_size    => default_ephemeral_disk_size,
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
            
            it "should return the specified disk size" do
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
              }.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is `invalid-size'."
            end
          end
        end
      end
    end
  end

  describe "#list_disks" do
    context "when the storage account does not contain any disk" do
      let(:blobs) { [] }

      before do
        allow(blob_manager).to receive(:list_blobs).
          and_return(blobs)
      end

      it "should return empty" do
        expect(disk_manager.list_disks(storage_account_name)).to eq([])
      end
    end

    context "when the storage account contains disks" do
      let(:blobs) {
        [
          double("blob", :name => "a.status"),
          double("blob", :name => "b.status"),
          double("blob", :name => "c.vhd"),
          double("blob", :name => "d.vhd")
        ]
      }

      before do
        allow(blob_manager).to receive(:list_blobs).
          and_return(blobs)
      end

      it "should return correct value" do
        disks = disk_manager.list_disks(storage_account_name)
        expect(disks).to eq(
          [
            { :disk_name => 'c' },
            { :disk_name => 'd' },
          ]
        )
      end
    end
  end
end
