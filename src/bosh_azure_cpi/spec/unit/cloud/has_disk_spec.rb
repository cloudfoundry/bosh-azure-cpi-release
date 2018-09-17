# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#has_disk?' do
    let(:disk_cid) { 'fake-disk-id' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .with(disk_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(disk_id_object)

      allow(telemetry_manager).to receive(:monitor)
        .with('has_disk?', id: disk_cid).and_call_original
    end

    context 'when disk name starts with DATA_DISK_PREFIX' do
      before do
        allow(disk_id_object).to receive(:disk_name)
          .and_return('bosh-data-abc')
      end

      context 'when use_managed_disks is true' do
        context 'when the managed disk exists' do
          before do
            allow(disk_manager2).to receive(:has_data_disk?).with(disk_id_object).and_return(true)
          end

          it 'should return true' do
            expect(managed_cloud.has_disk?(disk_cid)).to be(true)
          end
        end

        context 'when the managed disk does not exist' do
          before do
            allow(disk_manager2).to receive(:has_data_disk?).with(disk_id_object).and_return(false)
          end

          context 'when the disk has been migrated from unmanaged to managed' do
            before do
              allow(disk_manager).to receive(:is_migrated?).with(disk_id_object).and_return(true)
            end

            it 'should return false' do
              expect(disk_manager).not_to receive(:has_data_disk?)
              expect(managed_cloud.has_disk?(disk_cid)).to be(false)
            end
          end

          context 'when the disk is not migrated from unmanaged to managed' do
            before do
              allow(disk_manager).to receive(:is_migrated?).with(disk_id_object).and_return(false)
            end

            context 'when the unmanaged disk exists' do
              before do
                allow(disk_manager).to receive(:has_data_disk?).with(disk_id_object).and_return(true)
              end

              it 'should return true' do
                expect(managed_cloud.has_disk?(disk_cid)).to be(true)
              end
            end

            context 'when the unmanaged disk does not exist' do
              before do
                allow(disk_manager).to receive(:has_data_disk?).with(disk_id_object).and_return(false)
              end

              it 'should return false' do
                expect(managed_cloud.has_disk?(disk_cid)).to be(false)
              end
            end
          end
        end
      end

      context 'when use_managed_disks is false' do
        context 'when the unmanaged disk exists' do
          before do
            allow(disk_manager).to receive(:has_data_disk?).with(disk_id_object).and_return(true)
          end

          it 'should return true' do
            expect(cloud.has_disk?(disk_cid)).to be(true)
          end
        end

        context 'when the unmanaged disk does not exist' do
          before do
            allow(disk_manager).to receive(:has_data_disk?).with(disk_id_object).and_return(false)
          end

          it 'should return false' do
            expect(cloud.has_disk?(disk_cid)).to be(false)
          end
        end
      end
    end

    context 'when disk name starts with MANAGED_DATA_DISK_PREFIX' do
      before do
        allow(disk_id_object).to receive(:disk_name)
          .and_return('bosh-disk-data-abc')
      end

      context 'when the managed disk exists' do
        before do
          allow(disk_manager2).to receive(:has_data_disk?).with(disk_id_object).and_return(true)
        end

        it 'should return true' do
          expect(managed_cloud.has_disk?(disk_cid)).to be(true)
        end
      end

      context 'when the managed disk does not exist' do
        before do
          allow(disk_manager2).to receive(:has_data_disk?).with(disk_id_object).and_return(false)
        end

        it 'should return false' do
          expect(managed_cloud.has_disk?(disk_cid)).to be(false)
        end
      end
    end
  end
end
