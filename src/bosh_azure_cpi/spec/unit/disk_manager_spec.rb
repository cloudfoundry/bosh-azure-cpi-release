# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::DiskManager do
  let(:azure_config) { mock_azure_config }
  let(:props_factory) { Bosh::AzureCloud::PropsFactory.new(Bosh::AzureCloud::ConfigFactory.build(mock_cloud_options['properties'])) }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { Bosh::AzureCloud::DiskManager.new(azure_config, blob_manager) }
  let(:disk_id) { instance_double(Bosh::AzureCloud::DiskId) }
  let(:snapshot_id) { instance_double(Bosh::AzureCloud::DiskId) }

  let(:storage_account_name) { 'fake_storage_account_name' }
  let(:disk_name) { 'fake-disk-name' }
  let(:caching) { 'fake-caching' }

  let(:disk_container) { 'bosh' }
  let(:os_disk_prefix) { 'bosh-os' }
  let(:data_disk_prefix) { 'bosh-data' }

  before do
    allow(disk_id).to receive(:disk_name).and_return(disk_name)
    allow(disk_id).to receive(:caching).and_return(caching)
    allow(disk_id).to receive(:storage_account_name).and_return(storage_account_name)
  end

  describe '#delete_disk' do
    context 'when the disk exists' do
      before do
        allow(blob_manager).to receive(:get_blob_properties)
          .and_return({})
      end

      it 'deletes the disk' do
        expect(blob_manager).to receive(:delete_blob)
          .with(storage_account_name, disk_container, "#{disk_name}.vhd")

        expect do
          disk_manager.delete_disk(storage_account_name, disk_name)
        end.not_to raise_error
      end
    end

    context 'when the disk does not exist' do
      before do
        allow(blob_manager).to receive(:get_blob_properties)
          .and_return(nil)
      end

      it 'does not delete the disk' do
        expect(blob_manager).not_to receive(:delete_blob)

        expect do
          disk_manager.delete_disk(storage_account_name, disk_name)
        end.not_to raise_error
      end
    end
  end

  describe '#delete_data_disk' do
    it 'should delete the disk' do
      expect(disk_manager).to receive(:delete_disk)
        .with(storage_account_name, disk_name)

      expect do
        disk_manager.delete_data_disk(disk_id)
      end.not_to raise_error
    end
  end

  describe '#delete_vm_status_files' do
    context 'when there are several vm status file' do
      before do
        allow(blob_manager).to receive(:list_blobs)
          .and_return([
                        double('blob', name: 'a.status'),
                        double('blob', name: 'b.status'),
                        double('blob', name: 'a.vhd'),
                        double('blob', name: 'b.vhd')
                      ])
      end

      it 'deletes vm status files' do
        expect(blob_manager).to receive(:delete_blob)
          .with(storage_account_name, 'bosh', 'a.status')
        expect(blob_manager).to receive(:delete_blob)
          .with(storage_account_name, 'bosh', 'b.status')

        expect do
          disk_manager.delete_vm_status_files(storage_account_name, '')
        end.not_to raise_error
      end
    end

    context 'when there are no vm status file' do
      before do
        allow(blob_manager).to receive(:list_blobs)
          .and_return([])
      end

      it "doesn't delete vm status files" do
        expect(blob_manager).not_to receive(:delete_blob)

        expect do
          disk_manager.delete_vm_status_files(storage_account_name, '')
        end.not_to raise_error
      end
    end

    context 'when an exception is raised when deleting the files' do
      before do
        allow(blob_manager).to receive(:list_blobs)
          .and_return([
                        double('blob', name: 'a.status'),
                        double('blob', name: 'b.status'),
                        double('blob', name: 'a.vhd'),
                        double('blob', name: 'b.vhd')
                      ])
        allow(blob_manager).to receive(:delete_blob).and_raise(StandardError)
      end

      it "ignores the exception and doesn't raise error" do
        expect do
          disk_manager.delete_vm_status_files(storage_account_name, '')
        end.not_to raise_error
      end
    end
  end

  describe '#snapshot_disk' do
    let(:metadata) { {} }
    let(:snapshot_time) { 'fake-snapshot-time' }

    it 'returns the snapshot disk name' do
      allow(blob_manager).to receive(:snapshot_blob)
        .with(storage_account_name, disk_container, "#{disk_name}.vhd", metadata)
        .and_return(snapshot_time)

      snapshot_name = disk_manager.snapshot_disk(storage_account_name, disk_name, metadata)
      expect(snapshot_name).to include(disk_name)
      expect(snapshot_name).to include(snapshot_time)
    end
  end

  describe '#delete_snapshot' do
    context 'when snapshot id is in-valid' do
      let(:snapshot_name) { 'invalide-snapshot-name' }

      before do
        allow(snapshot_id).to receive(:storage_account_name).and_return(storage_account_name)
        allow(snapshot_id).to receive(:disk_name).and_return(snapshot_name)
      end

      it 'should raise an error' do
        expect do
          disk_manager.delete_snapshot(snapshot_id)
        end.to raise_error /Invalid snapshot id/
      end
    end

    context 'when snapshot id is valid' do
      let(:snapshot_time) { 'fake-snapshot-time' }
      let(:snapshot_name) { "#{disk_name}--#{snapshot_time}" }

      before do
        allow(snapshot_id).to receive(:storage_account_name).and_return(storage_account_name)
        allow(snapshot_id).to receive(:disk_name).and_return(snapshot_name)
      end

      it 'deletes the snapshot' do
        expect(blob_manager).to receive(:delete_blob_snapshot)
          .with(storage_account_name, disk_container, "#{disk_name}.vhd", snapshot_time)

        expect do
          disk_manager.delete_snapshot(snapshot_id)
        end.not_to raise_error
      end
    end
  end

  describe '#create_disk' do
    let(:size) { 100 }
    let(:caching) { 'ReadOnly' }

    it 'returns the disk name with the specified caching' do
      expect(blob_manager).to receive(:create_empty_vhd_blob)
        .with(storage_account_name, disk_container, "#{disk_name}.vhd", size)

      expect do
        disk_manager.create_disk(disk_id, size)
      end.not_to raise_error
    end
  end

  describe '#has_data_disk?' do
    before do
      allow(blob_manager).to receive(:get_blob_properties)
        .and_return({})
    end
    it 'should delete the disk' do
      expect(disk_manager.has_data_disk?(disk_id)).to be(true)
    end
  end

  describe '#is_migrated?' do
    context 'when the disk does not exist' do
      before do
        allow(blob_manager).to receive(:get_blob_properties)
          .and_return(nil)
      end

      it 'should return false' do
        expect(disk_manager.has_data_disk?(disk_id)).to be(false)
        expect(disk_manager.is_migrated?(disk_id)).to be(false)
      end
    end

    context 'when the disk exists' do
      before do
        allow(blob_manager).to receive(:get_blob_properties)
          .and_return({})
      end

      context 'when the disk has the metadata' do
        let(:metadata) do
          {
            'user_agent' => 'bosh',
            'migrated' => 'true'
          }
        end
        before do
          allow(blob_manager).to receive(:get_blob_metadata)
            .and_return(metadata)
        end

        it 'should return true' do
          expect(disk_manager.is_migrated?(disk_id)).to be(true)
        end
      end

      context "when the disk doesn't have the metadata" do
        let(:metadata) { {} }
        before do
          allow(blob_manager).to receive(:get_blob_metadata)
            .and_return(metadata)
        end

        it 'should return false' do
          expect(disk_manager.is_migrated?(disk_id)).to be(false)
        end
      end
    end
  end

  describe '#get_disk_uri' do
    it 'returns the right disk uri' do
      expect(blob_manager).to receive(:get_blob_uri)
        .with(storage_account_name, disk_container, "#{disk_name}.vhd")
        .and_return('fake-uri')
      expect(disk_manager.get_disk_uri(storage_account_name, disk_name)).to eq('fake-uri')
    end
  end

  describe '#get_data_disk_uri' do
    it 'should get disk uri' do
      expect(disk_manager).to receive(:get_disk_uri)
        .with(storage_account_name, disk_name)

      expect do
        disk_manager.get_data_disk_uri(disk_id)
      end.not_to raise_error
    end
  end

  describe '#get_disk_size_in_gb' do
    let(:disk_size) { 42 * 1024 * 1024 * 1024 }

    before do
      expect(blob_manager).to receive(:get_blob_size_in_bytes)
        .with(storage_account_name, disk_container, "#{disk_name}.vhd")
        .and_return(disk_size)
    end

    it 'returns the disk size' do
      expect(disk_manager.get_disk_size_in_gb(disk_id)).to eq(42)
    end
  end

  describe '#generate_os_disk_name' do
    let(:vm_name) { 'fake-vm-name' }

    it 'returns the right os disk name' do
      expect(disk_manager.generate_os_disk_name(vm_name)).to eq("#{os_disk_prefix}-fake-vm-name")
    end
  end

  describe '#generate_ephemeral_disk_name' do
    let(:vm_name) { 'fake-vm-name' }

    it 'returns the right ephemeral disk name' do
      expect(disk_manager.generate_ephemeral_disk_name(vm_name)).to eq("#{os_disk_prefix}-fake-vm-name-ephemeral-disk")
    end
  end

  describe '#os_disk' do
    let(:disk_uri) { 'fake-disk-uri' }
    let(:vm_name) { 'fake-vm-name' }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }
    let(:image_size) { 3 * 1024 }

    before do
      allow(disk_manager).to receive(:generate_os_disk_name)
        .and_return(disk_name)
      allow(disk_manager).to receive(:get_disk_uri)
        .and_return(disk_uri)
      allow(stemcell_info).to receive(:image_size)
        .and_return(image_size)
      allow(stemcell_info).to receive(:is_windows?)
        .and_return(false)
    end

    # Caching
    context 'when caching is not specified' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'STANDARD_A1'
        )
      end

      it 'should return the default caching for os disk: ReadWrite' do
        expect(
          disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ).to eq(
          disk_name: disk_name,
          disk_uri: disk_uri,
          disk_size: nil,
          disk_caching: 'ReadWrite'
        )
      end
    end

    context 'when caching is specified' do
      context 'when caching is valid' do
        let(:disk_caching) { 'ReadOnly' }
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'STANDARD_A1',
            'caching' => disk_caching
          )
        end

        it 'should return the specified caching' do
          expect(
            disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
            disk_uri: disk_uri,
            disk_size: nil,
            disk_caching: disk_caching
          )
        end
      end

      context 'when caching is invalid' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'STANDARD_A1',
            'caching' => 'invalid'
          )
        end

        it 'should raise an error' do
          expect do
            disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
          end.to raise_error /Unknown disk caching/
        end
      end
    end

    # Disk Size
    context 'without root_disk' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'STANDARD_A1'
        )
      end

      it 'should return disk_size: nil' do
        expect(
          disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ).to eq(
          disk_name: disk_name,
          disk_uri: disk_uri,
          disk_size: nil,
          disk_caching: 'ReadWrite'
        )
      end
    end

    context 'with root_disk' do
      context 'when size is not specified' do
        context 'with the ephemeral disk' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {}
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: nil,
              disk_caching: 'ReadWrite'
            )
          end
        end

        context 'without the ephemeral disk' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {},
              'ephemeral_disk' => {
                'use_root_disk' => true
              }
            )
          end

          context 'when the OS is Linux' do
            let(:minimum_required_disk_size) { 30 }
            context 'when the image_size is smaller than minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size - 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return the minimum required disk size' do
                expect(
                  disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
                  disk_uri: disk_uri,
                  disk_size: minimum_required_disk_size,
                  disk_caching: 'ReadWrite'
                )
              end
            end

            context 'when the image_size is larger than minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size + 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return image_size as the disk size' do
                expect(
                  disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
                  disk_uri: disk_uri,
                  disk_size: image_size / 1024,
                  disk_caching: 'ReadWrite'
                )
              end
            end
          end

          context 'when the OS is Windows' do
            let(:minimum_required_disk_size) { 128 }
            before do
              allow(stemcell_info).to receive(:is_windows?)
                .and_return(true)
            end

            context 'when the image_size is smaller than minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size - 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return the minimum required disk size' do
                expect(
                  disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
                  disk_uri: disk_uri,
                  disk_size: minimum_required_disk_size,
                  disk_caching: 'ReadWrite'
                )
              end
            end

            context 'when the image_size is larger than minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size + 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return image_size as the disk size' do
                expect(
                  disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
                  disk_uri: disk_uri,
                  disk_size: image_size / 1024,
                  disk_caching: 'ReadWrite'
                )
              end
            end
          end
        end
      end

      context 'when size is specified' do
        context 'When the size is not an integer' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 'invalid-size'
              }
            )
          end

          it 'should raise an error' do
            expect do
              disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            end.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is 'invalid-size'."
          end
        end

        context 'When the size is smaller than image_size' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 2 * 1024
              }
            )
          end
          let(:image_size) { 4 * 1024 }
          before do
            allow(stemcell_info).to receive(:image_size)
              .and_return(image_size)
          end

          it 'should use the image_size' do
            expect(
              disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: 4,
              disk_caching: 'ReadWrite'
            )
          end
        end

        context 'When the size is divisible by 1024' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 5 * 1024
              }
            )
          end

          it 'should return the correct disk_size' do
            expect(
              disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: 5,
              disk_caching: 'ReadWrite'
            )
          end
        end

        context 'When the size is not divisible by 1024' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'root_disk' => {
                'size' => 5 * 1024 + 512
              }
            )
          end

          it 'should return the smallest Integer greater than or equal to size/1024 for disk_size' do
            expect(
              disk_manager.os_disk(storage_account_name, vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: 6,
              disk_caching: 'ReadWrite'
            )
          end
        end
      end
    end
  end

  describe '#ephemeral_disk' do
    let(:disk_name) { 'ephemeral-disk' } # EPHEMERAL_DISK_POSTFIX
    let(:disk_uri) { 'fake-disk-uri' }
    let(:vm_name) { 'fake-vm-name' }
    let(:default_ephemeral_disk_size) { 70 } # The default value is default_ephemeral_disk_size for Standard_A1

    before do
      allow(disk_manager).to receive(:get_disk_uri)
        .and_return(disk_uri)
    end

    context 'without ephemeral_disk' do
      context 'with a valid instance_type' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'STANDARD_A1'
          )
        end

        it 'should return correct values' do
          expect(
            disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
            disk_uri: disk_uri,
            disk_size: default_ephemeral_disk_size,
            disk_caching: 'ReadWrite'
          )
        end
      end

      context 'with an invalid instance_type' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'invalid-instance-type'
          )
        end

        it 'should return 30 as the default disk size' do
          expect(
            disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
            disk_uri: disk_uri,
            disk_size: 30,
            disk_caching: 'ReadWrite'
          )
        end
      end
    end

    context 'with ephemeral_disk' do
      context 'with use_root_disk' do
        context 'when use_root_disk is false' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {
                'use_root_disk' => false
              }
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: default_ephemeral_disk_size,
              disk_caching: 'ReadWrite'
            )
          end
        end

        context 'when use_root_disk is true' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {
                'use_root_disk' => true
              }
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
            ).to be_nil
          end
        end
      end

      context 'without use_root_disk' do
        context 'without size' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {}
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_uri: disk_uri,
              disk_size: default_ephemeral_disk_size,
              disk_caching: 'ReadWrite'
            )
          end
        end

        context 'with size' do
          context 'when the size is valid' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'STANDARD_A1',
                'ephemeral_disk' => {
                  'size' => 30 * 1024
                }
              )
            end

            it 'should return the specified disk size' do
              expect(
                disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
              ).to eq(
                disk_name: disk_name,
                disk_uri: disk_uri,
                disk_size: 30,
                disk_caching: 'ReadWrite'
              )
            end
          end

          context 'when the size is not an integer' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'STANDARD_A1',
                'ephemeral_disk' => {
                  'size' => 'invalid-size'
                }
              )
            end

            it 'should raise an error' do
              expect do
                disk_manager.ephemeral_disk(storage_account_name, vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
              end.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is 'invalid-size'."
            end
          end
        end
      end
    end
  end

  describe '#list_disks' do
    context 'when the storage account does not contain any disk' do
      let(:blobs) { [] }

      before do
        allow(blob_manager).to receive(:list_blobs)
          .and_return(blobs)
      end

      it 'should return empty' do
        expect(disk_manager.list_disks(storage_account_name)).to eq([])
      end
    end

    context 'when the storage account contains disks' do
      let(:blobs) do
        [
          double('blob', name: 'a.status'),
          double('blob', name: 'b.status'),
          double('blob', name: 'c.vhd'),
          double('blob', name: 'd.vhd')
        ]
      end

      before do
        allow(blob_manager).to receive(:list_blobs)
          .and_return(blobs)
      end

      it 'should return correct value' do
        disks = disk_manager.list_disks(storage_account_name)
        expect(disks).to eq(
          [
            { disk_name: 'c' },
            { disk_name: 'd' }
          ]
        )
      end
    end
  end
end
