require 'spec_helper'

describe Bosh::AzureCloud::DiskManager2 do
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:disk_manager2) { Bosh::AzureCloud::DiskManager2.new(client2) }

  let(:managed_os_disk_prefix) { "bosh-disk-os" }
  let(:managed_data_disk_prefix) { "bosh-disk-data" }
  let(:uuid) { "c691bf30-b72c-44de-907e-8b80823ec848" }
  let(:disk_name) { "#{managed_data_disk_prefix}-#{uuid}-None" }

  before do
    allow(SecureRandom).to receive(:uuid).and_return(uuid)
  end

  describe "#create_disk" do
    # Parameters
    let(:location) { "SouthEastAsia" }
    let(:size) { 100 }
    let(:storage_account_type) { "fake-storage-account-type" }
    let(:caching) { "ReadOnly" }

    let(:disk_name) { "#{managed_data_disk_prefix}-#{uuid}-#{caching}" }
    let(:disk_params) {
      {
        :name => disk_name,
        :location => location,
        :tags => {
          "user-agent" => "bosh",
          "caching" => caching
        },
        :disk_size => size,
        :account_type => storage_account_type
      }
    }

    it "creates the disk with the specified caching and storage account type" do
      expect(client2).to receive(:create_empty_managed_disk).with(disk_params)
      expect {
        disk_manager2.create_disk(location, size, storage_account_type, caching)
      }.not_to raise_error
    end
  end  

  describe "#create_disk_from_blob" do
    let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
    let(:blob_data_disk_prefix) { "bosh-data" }
    let(:disk_name) { "#{blob_data_disk_prefix}-#{storage_account_name}-#{uuid}-None" }
    let(:blob_uri) { "fake-blob-uri" }
    let(:location) { "SouthEastAsia" }
    let(:storage_account_type) { "Standard_LRS" }

    let(:disk_params) {
      {
        :name => disk_name,
        :location => location,
        :tags => {
          "user-agent" => "bosh",
          "caching" => "None",
          "original_blob" => blob_uri
        },
        :source_uri => blob_uri,
        :account_type => "Standard_LRS"
      }
    }

    it "creates the managed disk from the blob uri" do
      expect(client2).to receive(:create_managed_disk_from_blob).with(disk_params)
      expect {
        disk_manager2.create_disk_from_blob(disk_name, blob_uri, location, storage_account_type)
      }.not_to raise_error
    end
  end  

  describe "#delete_disk" do
    context "when the disk exists" do
      before do
        allow(client2).to receive(:get_managed_disk_by_name).
          with(disk_name).
          and_return({})
      end

      context "when AzureConflictError is not thrown" do
        it "deletes the disk" do
          expect(client2).to receive(:delete_managed_disk).
            with(disk_name).once

          expect {
            disk_manager2.delete_disk(disk_name)
          }.not_to raise_error
        end
      end

      context "when AzureConflictError is thrown only one time" do
        it "do one retry and deletes the disk" do
          expect(client2).to receive(:delete_managed_disk).
            with(disk_name).
            and_raise(Bosh::AzureCloud::AzureConflictError)
          expect(client2).to receive(:delete_managed_disk).
            with(disk_name).once

          expect {
            disk_manager2.delete_disk(disk_name)
          }.not_to raise_error
        end
      end

      context "when AzureConflictError is thrown every time" do
        before do
          allow(client2).to receive(:delete_managed_disk).
            with(disk_name).
            and_raise(Bosh::AzureCloud::AzureConflictError)
        end

        it "raise an error because the retry still fails" do
          expect {
            disk_manager2.delete_disk(disk_name)
          }.to raise_error Bosh::AzureCloud::AzureConflictError
        end
      end
    end

    context "when the disk does not exist" do
      before do
        allow(client2).to receive(:get_managed_disk_by_name).
          with(disk_name).
          and_return(nil)
      end

      it "does not delete the disk" do
        expect(client2).not_to receive(:delete_managed_disk).
          with(disk_name)

        expect {
          disk_manager2.delete_disk(disk_name)
        }.not_to raise_error
      end
    end
  end  

  describe "#has_disk?" do
    context "when the disk exists" do
      before do
        allow(client2).to receive(:get_managed_disk_by_name).
          with(disk_name).
          and_return({})
      end

      it "should return true" do
        expect(disk_manager2.has_disk?(disk_name)).to be(true)
      end
    end

    context "when the disk does not exist" do
      before do
        allow(client2).to receive(:get_managed_disk_by_name).
          with(disk_name).
          and_return(nil)
      end

      it "should return false" do
        expect(disk_manager2.has_disk?(disk_name)).to be(false)
      end
    end
  end

  describe "#get_disk" do
    let(:disk) {
      { :name => "fake-name" }
    }
    before do
      allow(client2).to receive(:get_managed_disk_by_name).
        with(disk_name).
        and_return(disk)
    end

    it "should get the disk" do
      expect(disk_manager2.get_disk(disk_name)).to be(disk)
    end
  end

  describe "#snapshot_disk" do
    let(:metadata) { {"foo" => "bar"} }
    let(:snapshot_name) { "#{managed_data_disk_prefix}-#{uuid}-None" }
    let(:snapshot_params) {
      {
        :name => snapshot_name,
        :tags => {
          "foo" => "bar",
          "original" => disk_name
        },
        :disk_name => disk_name
      }
    }

    it "creates the managed snapshot" do
      expect(client2).to receive(:create_managed_snapshot).with(snapshot_params)

      expect {
        disk_manager2.snapshot_disk(disk_name, metadata)
      }.not_to raise_error
    end
  end  

  describe "#delete_snapshot" do
    let(:snapshot_name) { "#{managed_data_disk_prefix}-#{uuid}-None" }

    it "deletes the snapshot" do
      expect(client2).to receive(:delete_managed_snapshot).with(snapshot_name)

      disk_manager2.delete_snapshot(snapshot_name)
    end
  end  

  describe "#generate_os_disk_name" do
    let(:instance_id) { "fake-instance-id" }

    it "returns the right os disk name" do
      expect(disk_manager2.generate_os_disk_name(instance_id)).to eq("#{managed_os_disk_prefix}-fake-instance-id")
    end
  end

  describe "#generate_ephemeral_disk_name" do
    let(:instance_id) { "fake-instance-id" }

    it "returns the right ephemeral disk name" do
      expect(disk_manager2.generate_ephemeral_disk_name(instance_id)).to eq("#{managed_os_disk_prefix}-fake-instance-id-ephemeral-disk")
    end
  end

  describe "#os_disk" do
    let(:disk_name) { 'fake-disk-name' }
    let(:instance_id) { 'fake-instance-id' }
    let(:minimum_disk_size) { 3072 }

    before do
      allow(disk_manager2).to receive(:generate_os_disk_name).
        and_return(disk_name)
    end

    context "without root_disk nor caching" do
      let(:resource_pool) {
        {
          'instance_type' => 'STANDARD_A1'
        }
      }

      it "should return correct values" do
        disk_manager2.resource_pool = resource_pool

        expect(
          disk_manager2.os_disk(instance_id, minimum_disk_size)
        ).to eq(
          {
            :disk_name    => disk_name,
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
          disk_manager2.resource_pool = resource_pool

          expect(
            disk_manager2.os_disk(instance_id, minimum_disk_size)
          ).to eq(
            {
              :disk_name    => disk_name,
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
          disk_manager2.resource_pool = resource_pool

          expect {
            disk_manager2.os_disk(instance_id, minimum_disk_size)
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
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            ).to eq(
              {
                :disk_name    => disk_name,
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
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            ).to eq(
              {
                :disk_name    => disk_name,
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
          disk_manager2.resource_pool = resource_pool

          expect(
            disk_manager2.os_disk(instance_id, minimum_disk_size)
          ).to eq(
            {
              :disk_name    => disk_name,
              :disk_size    => 3,
              :disk_caching => 'ReadWrite'
            }
          )
        end
      end

      context "with an invalid size" do
        context "When minimum_disk_size is not specified and the size is smaller than 3 GiB" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 2 * 1024
              }
            }
          }

          it "should raise an error" do
            disk_manager2.resource_pool = resource_pool

            expect {
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            }.to raise_error /root_disk.size `2048' is smaller than the default OS disk size `3072' MiB/
          end
        end

        context "When minimum_disk_size is specified and the size is smaller than minimum_disk_size" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 2 * 1024
              }
            }
          }
          let(:minimum_disk_size) { 4 * 1024 }

          it "should raise an error" do
            disk_manager2.resource_pool = resource_pool

            expect {
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            }.to raise_error /root_disk.size `2048' is smaller than the default OS disk size `4096' MiB/
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
            disk_manager2.resource_pool = resource_pool

            expect {
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            }.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is `invalid-size'."
          end
        end

        context "When the size is not divisible by 1024" do
          let(:resource_pool) {
            {
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 5*1024 + 512
              }
            }
          }

          it "should return the smallest Integer greater than or equal to size/1024 for disk_size" do
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.os_disk(instance_id, minimum_disk_size)
            ).to eq(
              {
                :disk_name    => disk_name,
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
    let(:instance_id) { 'fake-instance-id' }
    let(:disk_name) { "#{managed_os_disk_prefix}-#{instance_id}-ephemeral-disk" }

    context "without ephemeral_disk" do
      context "with a valid instance_type" do
        let(:resource_pool) {
          {
            'instance_type' => 'STANDARD_A1'
          }
        }

        it "should return correct values" do
          disk_manager2.resource_pool = resource_pool

          expect(
            disk_manager2.ephemeral_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
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
          disk_manager2.resource_pool = resource_pool

          expect(
            disk_manager2.ephemeral_disk(instance_id)
          ).to eq(
            {
              :disk_name    => disk_name,
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
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.ephemeral_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
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
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.ephemeral_disk(instance_id)
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
            disk_manager2.resource_pool = resource_pool

            expect(
              disk_manager2.ephemeral_disk(instance_id)
            ).to eq(
              {
                :disk_name    => disk_name,
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
              disk_manager2.resource_pool = resource_pool

              expect {
                disk_manager2.ephemeral_disk(instance_id)
              }.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is `invalid-size'."
            end
          end
        end
      end
    end
  end

  describe "#get_data_disk_caching" do
    it "returns the right caching" do
      expect(disk_manager2.get_data_disk_caching(disk_name)).to eq("None")
    end
  end

end
