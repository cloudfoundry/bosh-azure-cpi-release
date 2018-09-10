# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#delete_disk' do
    let(:disk_cid) { 'fake-disk-id' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }

    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('delete_disk', id: disk_cid).and_call_original
    end

    context 'when use_managed_disks is true' do
      before do
        allow(Bosh::AzureCloud::DiskId).to receive(:parse)
          .with(disk_cid, azure_config_managed.resource_group_name)
          .and_return(disk_id_object)
      end

      context 'when the disk is a newly-created managed disk' do
        let(:disk_name) { 'bosh-disk-data-guid' }

        before do
          allow(disk_id_object).to receive(:disk_name)
            .and_return(disk_name)
        end

        it 'should delete the managed disk' do
          expect(disk_manager2).to receive(:delete_data_disk).with(disk_id_object)
          expect do
            managed_cloud.delete_disk(disk_cid)
          end.not_to raise_error
        end
      end

      context 'when the disk is a managed disk which is created from a blob disk' do
        let(:disk_name) { 'bosh-data-guid' }
        let(:disk) { double('disk') }

        before do
          allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(disk)
          allow(disk_id_object).to receive(:disk_name)
            .and_return(disk_name)
        end

        it 'should delete the managed disk' do
          expect(disk_manager2).to receive(:delete_data_disk).with(disk_id_object)
          expect(disk_manager).not_to receive(:delete_data_disk)
          expect do
            managed_cloud.delete_disk(disk_cid)
          end.not_to raise_error
        end
      end

      context 'when the disk is an unmanaged disk' do
        let(:disk_name) { 'bosh-data-guid' }

        before do
          allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(nil)
          allow(disk_id_object).to receive(:disk_name)
            .and_return(disk_name)
        end

        it 'should delete the unmanaged disk' do
          expect(disk_manager2).not_to receive(:delete_data_disk)
          expect(disk_manager).to receive(:delete_data_disk).with(disk_id_object)
          expect do
            managed_cloud.delete_disk(disk_cid)
          end.not_to raise_error
        end
      end
    end

    context 'when use_managed_disks is false' do
      before do
        allow(Bosh::AzureCloud::DiskId).to receive(:parse)
          .with(disk_cid, azure_config.resource_group_name)
          .and_return(disk_id_object)
      end

      it 'should delete the unmanaged disk' do
        expect(disk_manager).to receive(:delete_data_disk).with(disk_id_object)
        expect do
          cloud.delete_disk(disk_cid)
        end.not_to raise_error
      end
    end
  end
end
