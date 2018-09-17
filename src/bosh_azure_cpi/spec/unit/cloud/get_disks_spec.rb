# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#get_disks' do
    let(:vm_cid) { 'fake-vm-cid' }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    let(:data_disks) do
      [
        {
          name: 'fake-data-disk-1',
          disk_bosh_id: 'fake-id-1'
        }, {
          name: 'fake-data-disk-2',
          disk_bosh_id: 'fake-id-2'
        }, {
          name: 'fake-data-disk-3',
          disk_bosh_id: 'fake-id-3'
        }
      ]
    end
    let(:instance) do
      {
        data_disks: data_disks
      }
    end
    let(:instance_no_disks) do
      {
        data_disks: {}
      }
    end

    before do
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .and_return(instance_id_object)

      allow(telemetry_manager).to receive(:monitor)
        .with('get_disks', id: vm_cid).and_call_original
    end

    context 'when the instance has data disks' do
      it 'should get a list of disk id' do
        expect(vm_manager).to receive(:find)
          .with(instance_id_object)
          .and_return(instance)

        expect(cloud.get_disks(vm_cid)).to eq(['fake-id-1', 'fake-id-2', 'fake-id-3'])
      end
    end

    context 'when the instance has no data disk' do
      it 'should get a empty list' do
        expect(vm_manager).to receive(:find)
          .with(instance_id_object)
          .and_return(instance_no_disks)

        expect(cloud.get_disks(vm_cid)).to eq([])
      end
    end
  end
end
