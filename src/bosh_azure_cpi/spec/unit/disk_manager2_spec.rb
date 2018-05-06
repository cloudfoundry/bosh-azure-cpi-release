# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::DiskManager2 do
  let(:props_factory) { Bosh::AzureCloud::PropsFactory.new(Bosh::AzureCloud::ConfigFactory.build(mock_cloud_options['properties'])) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:disk_manager2) { Bosh::AzureCloud::DiskManager2.new(azure_client) }
  let(:disk_id) { instance_double(Bosh::AzureCloud::DiskId) }
  let(:snapshot_id) { instance_double(Bosh::AzureCloud::DiskId) }

  let(:managed_os_disk_prefix) { 'bosh-disk-os' }
  let(:managed_data_disk_prefix) { 'bosh-disk-data' }
  let(:uuid) { 'c691bf30-b72c-44de-907e-8b80823ec848' }
  let(:disk_name) { 'fake-disk-name' }
  let(:caching) { 'fake-caching' }
  let(:resource_group_name) { 'fake-resource-group-name' }

  let(:snapshot_name) { 'fake-snapshot-name' }

  before do
    allow(SecureRandom).to receive(:uuid).and_return(uuid)
    allow(disk_id).to receive(:disk_name).and_return(disk_name)
    allow(disk_id).to receive(:caching).and_return(caching)
    allow(disk_id).to receive(:resource_group_name).and_return(resource_group_name)

    allow(snapshot_id).to receive(:disk_name).and_return(snapshot_name)
    allow(snapshot_id).to receive(:caching).and_return(caching)
    allow(snapshot_id).to receive(:resource_group_name).and_return(resource_group_name)
  end

  describe '#create_disk' do
    # Parameters
    let(:location) { 'SouthEastAsia' }
    let(:size) { 100 }
    let(:storage_account_type) { 'fake-storage-account-type' }
    let(:zone) { 'fake-zone' }

    let(:disk_params) do
      {
        name: disk_name,
        location: location,
        tags: {
          'user-agent' => 'bosh',
          'caching' => caching
        },
        disk_size: size,
        account_type: storage_account_type,
        zone: zone
      }
    end

    it 'creates the disk with the specified caching and storage account type' do
      expect(azure_client).to receive(:create_empty_managed_disk)
        .with(resource_group_name, disk_params)
      expect do
        disk_manager2.create_disk(disk_id, location, size, storage_account_type, zone)
      end.not_to raise_error
    end
  end

  describe '#create_disk_from_blob' do
    let(:blob_data_disk_prefix) { 'bosh-data' }
    let(:blob_uri) { 'fake-blob-uri' }
    let(:location) { 'SouthEastAsia' }
    let(:storage_account_type) { 'Standard_LRS' }
    let(:zone) { 'fake-zone' }

    let(:disk_params) do
      {
        name: disk_name,
        location: location,
        tags: {
          'user-agent' => 'bosh',
          'caching' => caching,
          'original_blob' => blob_uri
        },
        source_uri: blob_uri,
        account_type: storage_account_type,
        zone: zone
      }
    end

    it 'creates the managed disk from the blob uri' do
      expect(azure_client).to receive(:create_managed_disk_from_blob)
        .with(resource_group_name, disk_params)
      expect do
        disk_manager2.create_disk_from_blob(disk_id, blob_uri, location, storage_account_type, zone)
      end.not_to raise_error
    end
  end

  describe '#delete_disk' do
    context 'when the disk exists' do
      before do
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .with(resource_group_name, disk_name)
          .and_return({})
      end

      context 'when AzureConflictError is not thrown' do
        it 'deletes the disk' do
          expect(azure_client).to receive(:delete_managed_disk)
            .with(resource_group_name, disk_name).once

          expect do
            disk_manager2.delete_disk(resource_group_name, disk_name)
          end.not_to raise_error
        end
      end

      context 'when AzureConflictError is thrown only one time' do
        it 'do one retry and deletes the disk' do
          expect(azure_client).to receive(:delete_managed_disk)
            .with(resource_group_name, disk_name)
            .and_raise(Bosh::AzureCloud::AzureConflictError)
          expect(azure_client).to receive(:delete_managed_disk)
            .with(resource_group_name, disk_name).once

          expect do
            disk_manager2.delete_disk(resource_group_name, disk_name)
          end.not_to raise_error
        end
      end

      context 'when AzureConflictError is thrown every time' do
        before do
          allow(azure_client).to receive(:delete_managed_disk)
            .with(resource_group_name, disk_name)
            .and_raise(Bosh::AzureCloud::AzureConflictError)
        end

        it 'raise an error because the retry still fails' do
          expect do
            disk_manager2.delete_disk(resource_group_name, disk_name)
          end.to raise_error Bosh::AzureCloud::AzureConflictError
        end
      end
    end

    context 'when the disk does not exist' do
      before do
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .with(resource_group_name, disk_name)
          .and_return(nil)
      end

      it 'does not delete the disk' do
        expect(azure_client).not_to receive(:delete_managed_disk)
          .with(resource_group_name, disk_name)

        expect do
          disk_manager2.delete_disk(resource_group_name, disk_name)
        end.not_to raise_error
      end
    end
  end

  describe '#delete_data_disk' do
    it 'should delete the disk' do
      expect(disk_manager2).to receive(:delete_disk)
        .with(resource_group_name, disk_name)

      expect do
        disk_manager2.delete_data_disk(disk_id)
      end.not_to raise_error
    end
  end

  describe '#has_data_disk?' do
    context 'when the disk exists' do
      before do
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .with(resource_group_name, disk_name)
          .and_return({})
      end
      it 'should return true' do
        expect(disk_manager2.has_data_disk?(disk_id)).to be(true)
      end
    end

    context 'when the disk does not exist' do
      before do
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .with(resource_group_name, disk_name)
          .and_return(nil)
      end
      it 'should return false' do
        expect(disk_manager2.has_data_disk?(disk_id)).to be(false)
      end
    end
  end

  describe '#get_data_disk' do
    let(:mock_disk) { {} }
    it 'should get the disk' do
      expect do
        expect(azure_client).to receive(:get_managed_disk_by_name)
          .with(resource_group_name, disk_name)
          .and_return(mock_disk)
        disk_manager2.get_data_disk(disk_id)
      end.not_to raise_error
    end
  end

  describe '#snapshot_disk' do
    let(:metadata) { { 'foo' => 'bar' } }
    let(:snapshot_params) do
      {
        name: snapshot_name,
        tags: {
          'foo' => 'bar',
          'original' => disk_name
        },
        disk_name: disk_name
      }
    end

    it 'creates the managed snapshot' do
      expect(azure_client).to receive(:create_managed_snapshot).with(resource_group_name, snapshot_params)

      expect do
        disk_manager2.snapshot_disk(snapshot_id, disk_name, metadata)
      end.not_to raise_error
    end
  end

  describe '#delete_snapshot' do
    it 'deletes the snapshot' do
      expect(azure_client).to receive(:delete_managed_snapshot).with(resource_group_name, snapshot_name)

      expect do
        disk_manager2.delete_snapshot(snapshot_id)
      end.not_to raise_error
    end
  end

  describe '#has_snapshot?' do
    context 'when the snapshot exists' do
      before do
        allow(azure_client).to receive(:get_managed_snapshot_by_name)
          .with(resource_group_name, snapshot_name)
          .and_return({})
      end

      it 'should return true' do
        expect(disk_manager2.has_snapshot?(resource_group_name, snapshot_name)).to be(true)
      end
    end

    context 'when the snapshot does not exist' do
      before do
        allow(azure_client).to receive(:get_managed_snapshot_by_name)
          .with(resource_group_name, snapshot_name)
          .and_return(nil)
      end

      it 'should return false' do
        expect(disk_manager2.has_snapshot?(resource_group_name, snapshot_name)).to be(false)
      end
    end
  end

  describe '#generate_os_disk_name' do
    let(:vm_name) { 'fake-vm-name' }

    it 'returns the right os disk name' do
      expect(disk_manager2.generate_os_disk_name(vm_name)).to eq("#{managed_os_disk_prefix}-#{vm_name}")
    end
  end

  describe '#generate_ephemeral_disk_name' do
    let(:vm_name) { 'fake-vm-name' }

    it 'returns the right ephemeral disk name' do
      expect(disk_manager2.generate_ephemeral_disk_name(vm_name)).to eq("#{managed_os_disk_prefix}-#{vm_name}-ephemeral-disk")
    end
  end

  describe '#os_disk' do
    let(:vm_name) { 'fake-vm-name' }
    let(:disk_name) { 'fake-disk-name' }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }
    let(:image_size) { 3 * 1024 }

    before do
      allow(disk_manager2).to receive(:generate_os_disk_name)
        .and_return(disk_name)
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
          disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ).to eq(
          disk_name: disk_name,
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
            disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
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
            disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
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
          disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ).to eq(
          disk_name: disk_name,
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
              disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
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
            context 'when the image_size is smaller than the minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size - 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return the minimum required disk size' do
                expect(
                  disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
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
                  disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
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

            context 'when the image_size is smaller than the minimum required disk size' do
              let(:image_size) { (minimum_required_disk_size - 1) * 1024 }
              before do
                allow(stemcell_info).to receive(:image_size)
                  .and_return(image_size)
              end

              it 'should return the minimum required disk size' do
                expect(
                  disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
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
                  disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
                ).to eq(
                  disk_name: disk_name,
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
              disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
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
              disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
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
              disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
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
              disk_manager2.os_disk(vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_size: 6,
              disk_caching: 'ReadWrite'
            )
          end
        end
      end
    end
  end

  describe '#ephemeral_disk' do
    let(:vm_name) { 'fake-vm-name' }
    let(:disk_name) { "#{managed_os_disk_prefix}-#{vm_name}-ephemeral-disk" }
    let(:default_ephemeral_disk_size) { 70 } # The default value is default_ephemeral_disk_size for Standard_A1

    context 'without ephemeral_disk' do
      context 'with a valid instance_type' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'STANDARD_A1'
          )
        end

        it 'should return correct values' do
          expect(
            disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
            disk_size: default_ephemeral_disk_size,
            disk_caching: 'ReadWrite',
            disk_type: nil
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
            disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
          ).to eq(
            disk_name: disk_name,
            disk_size: 30,
            disk_caching: 'ReadWrite',
            disk_type: nil
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
              disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_size: default_ephemeral_disk_size,
              disk_caching: 'ReadWrite',
              disk_type: nil
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
              disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
            ).to be_nil
          end
        end
      end

      context 'without use_root_disk' do
        context 'with type' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {
                'type' => 'Premium_LRS'
              }
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_size: default_ephemeral_disk_size,
              disk_caching: 'ReadWrite',
              disk_type: 'Premium_LRS'
            )
          end
        end

        context 'without size' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'STANDARD_A1',
              'ephemeral_disk' => {}
            )
          end

          it 'should return correct values' do
            expect(
              disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
            ).to eq(
              disk_name: disk_name,
              disk_size: default_ephemeral_disk_size,
              disk_caching: 'ReadWrite',
              disk_type: nil
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

            it 'should return the specified size' do
              expect(
                disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
              ).to eq(
                disk_name: disk_name,
                disk_size: 30,
                disk_caching: 'ReadWrite',
                disk_type: nil
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
                disk_manager2.ephemeral_disk(vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
              end.to raise_error ArgumentError, "The disk size needs to be an integer. The current value is 'invalid-size'."
            end
          end
        end
      end
    end
  end

  describe '#migrate_to_zone' do
    let(:disk) do
      {
        location: 'fake-location',
        sku_name: 'fake-account-type',
        tags: {}
      }
    end
    let(:zone) { 'fake-zone' }
    let(:disk_params) do
      {
        name: disk_name,
        location: 'fake-location',
        zone: 'fake-zone',
        account_type: 'fake-account-type',
        tags: {}
      }
    end

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:create).and_return(snapshot_id)
      allow(disk_manager2).to receive(:snapshot_disk)
        .with(snapshot_id, disk_name, {})
      allow(disk_manager2).to receive(:has_snapshot?)
        .with(resource_group_name, snapshot_name)
        .and_return(true)
      allow(disk_manager2).to receive(:delete_disk)
        .with(resource_group_name, disk_name)
      allow(azure_client).to receive(:create_managed_disk_from_snapshot)
        .with(resource_group_name, disk_params, snapshot_name)
      allow(disk_manager2).to receive(:has_data_disk?)
        .with(disk_id)
        .and_return(true)
      allow(disk_manager2).to receive(:delete_snapshot)
        .with(snapshot_id)
    end

    context 'When everything is ok' do
      it 'should migrate the disk without error' do
        expect do
          disk_manager2.migrate_to_zone(disk_id, disk, zone)
        end.not_to raise_error
      end
    end

    context 'When the created snapshot does not exist' do
      before do
        allow(disk_manager2).to receive(:has_snapshot?)
          .with(resource_group_name, snapshot_name)
          .and_return(false)
      end

      it 'should raise an error' do
        expect do
          disk_manager2.migrate_to_zone(disk_id, disk, zone)
        end.to raise_error /migrate_to_zone - Can'n find snapshot '#{snapshot_name}' in resource group '#{resource_group_name}'/
      end
    end

    context 'When it fails to create disk from snapshot' do
      before do
        allow(azure_client).to receive(:create_managed_disk_from_snapshot)
          .with(resource_group_name, disk_params, snapshot_name)
          .and_raise('fails to create disk')
      end

      it 'should retry and raise an error finally' do
        expect(azure_client).to receive(:create_managed_disk_from_snapshot).exactly(3).times

        expect do
          disk_manager2.migrate_to_zone(disk_id, disk, zone)
        end.to raise_error /fails to create disk/
      end
    end

    context 'When it fails to create disk from snapshot but succeeds with retry' do
      it 'should migrate the disk without error' do
        count = 0
        allow(azure_client).to receive(:create_managed_disk_from_snapshot)
          .with(resource_group_name, disk_params, snapshot_name) do
            count += 1
            count == 1 ? raise('fails to create disk') : nil
          end

        expect(azure_client).to receive(:create_managed_disk_from_snapshot).exactly(2).times

        expect do
          disk_manager2.migrate_to_zone(disk_id, disk, zone)
        end.not_to raise_error
      end
    end

    context 'When the migrated disk does not exist' do
      before do
        allow(disk_manager2).to receive(:has_data_disk?)
          .with(disk_id)
          .and_return(false)
      end

      it 'should raise an error and not delete the snapshot' do
        expect(disk_manager2).not_to receive(:delete_snapshot)

        expect do
          disk_manager2.migrate_to_zone(disk_id, disk, zone)
        end.to raise_error /migrate_to_zone - Can'n find disk '#{disk_name}' in resource group '#{resource_group_name}' after migration/
      end
    end
  end
end
