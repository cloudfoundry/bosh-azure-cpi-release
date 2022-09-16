# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#resize_disk' do
    let(:disk_cid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:new_size) { 1_024_000 }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:disk_name) { 'fake-disk-name' }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .and_return(disk_id_object)
      allow(disk_id_object).to receive(:resource_group_name)
        .and_return(resource_group_name)
      allow(disk_id_object).to receive(:disk_name)
        .and_return(disk_name)
      allow(disk_manager2).to receive(:get_data_disk)
        .and_return({ disk_size: 512 })
      allow(telemetry_manager).to receive(:monitor)
        .with('resize_disk', id: disk_cid, extras: { 'disk_size' => new_size })
        .and_call_original
      allow(Bosh::Clouds::Config.logger).to receive(:info)
    end

    it 'should raise a NotSupported error if use_managed_disks is false' do
      expect do
        cloud.resize_disk(disk_cid, new_size)
      end.to raise_error(Bosh::Clouds::NotSupported)
    end

    context 'when trying to resize to a larger disk size multiple of 1024' do
      let(:new_size) { 1_024_000 }

      it 'should work' do
        expect(disk_manager2).to receive(:resize_disk).with(disk_id_object, 1000)
        expect(Bosh::Clouds::Config.logger).to receive(:info).with("Start resize of disk 'fake-disk-name' from 512 GiB to 1000 GiB")
        expect do
          managed_cloud.resize_disk(disk_cid, new_size)
        end.not_to raise_error
      end
    end

    context 'when trying to resize to a larger disk size not multiple of 1024' do
      let(:new_size) { 1_024_100 }

      it 'should work' do
        expect(disk_manager2).to receive(:resize_disk).with(disk_id_object, 1001)
        expect(Bosh::Clouds::Config.logger).to receive(:info).with("Start resize of disk 'fake-disk-name' from 512 GiB to 1001 GiB")
        expect do
          managed_cloud.resize_disk(disk_cid, new_size)
        end.not_to raise_error
      end
    end

    context 'when trying to resize to the same disk size' do
      let(:new_size) { 512 * 1024 }

      it 'should work' do
        expect(Bosh::Clouds::Config.logger).to receive(:info).with("Skip resize of disk 'fake-disk-name' because the new size of 512 GiB matches the actual disk size")
        expect do
          managed_cloud.resize_disk(disk_cid, new_size)
        end.not_to raise_error
      end
    end

    context 'when trying to resize to a smaller disk size' do
      let(:new_size) { 256_000 }

      it 'should raise a NotSupported error' do
        expect do
          managed_cloud.resize_disk(disk_cid, new_size)
        end.to raise_error(Bosh::Clouds::NotSupported)
      end
    end
  end
end
