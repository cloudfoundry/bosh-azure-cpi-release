require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#get_disks" do
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    let(:data_disks) {
      [
        {
          :name => "fake-data-disk-1",
        }, {
          :name => "fake-data-disk-2",
        }, {
          :name => "fake-data-disk-3",
        }
      ]
    }
    let(:instance) {
      {
        :data_disks    => data_disks,
      }
    }
    let(:instance_no_disks) {
      {
        :data_disks    => {},
      }
    }
  
    context 'when the instance has data disks' do
      it 'should get a list of disk id' do
        expect(vm_manager).to receive(:find).
          with(instance_id).
          and_return(instance)

        expect(cloud.get_disks(instance_id)).to eq(["fake-data-disk-1", "fake-data-disk-2", "fake-data-disk-3"])
      end
    end

    context 'when the instance has no data disk' do
      it 'should get a empty list' do
        expect(vm_manager).to receive(:find).
          with(instance_id).
          and_return(instance_no_disks)

        expect(cloud.get_disks(instance_id)).to eq([])
      end
    end
  end
end
