require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#has_disk?" do
    let(:disk_id) { "fake-disk-id" }

    context "when use_managed_disks is true" do
      context 'when the managed disk exists' do
        before do
          allow(disk_manager2).to receive(:has_disk?).with(disk_id).and_return(true)
        end

        it 'should return true' do
          expect(managed_cloud.has_disk?(disk_id)).to be(true)
        end
      end

      context 'when the managed disk does not exist' do
        before do
          allow(disk_manager2).to receive(:has_disk?).with(disk_id).and_return(false)
        end

        context 'when the disk has been migrated from unmanaged to managed' do
          before do
            allow(disk_manager).to receive(:is_migrated?).with(disk_id).and_return(true)
          end

          it 'should return false' do
            expect(disk_manager).not_to receive(:has_disk?)
            expect(managed_cloud.has_disk?(disk_id)).to be(false)
          end
        end

        context 'when the disk is not migrated from unmanaged to managed' do
          before do
            allow(disk_manager).to receive(:is_migrated?).with(disk_id).and_return(false)
          end

          context 'when the unmanaged disk exists' do
            before do
              allow(disk_manager).to receive(:has_disk?).with(disk_id).and_return(true)
            end

            it 'should return true' do
              expect(managed_cloud.has_disk?(disk_id)).to be(true)
            end
          end

          context 'when the unmanaged disk does not exist' do
            before do
              allow(disk_manager).to receive(:has_disk?).with(disk_id).and_return(false)
            end

            it 'should return false' do
              expect(managed_cloud.has_disk?(disk_id)).to be(false)
            end
          end
        end
      end
    end

    context "when use_managed_disks is false" do
      context 'when the unmanaged disk exists' do
        before do
          allow(disk_manager).to receive(:has_disk?).with(disk_id).and_return(true)
        end

        it 'should return true' do
          expect(cloud.has_disk?(disk_id)).to be(true)
        end
      end

      context 'when the unmanaged disk does not exist' do
        before do
          allow(disk_manager).to receive(:has_disk?).with(disk_id).and_return(false)
        end

        it 'should return false' do
          expect(cloud.has_disk?(disk_id)).to be(false)
        end
      end
    end
  end
end
