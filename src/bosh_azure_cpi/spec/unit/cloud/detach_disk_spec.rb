# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#detach_disk' do
    let(:instance_id) { 'fake-instance-id' }
    let(:disk_id) { 'fake-disk-id' }
    let(:host_device_id) { 'fake-host-device-id' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .and_return(disk_id_object)
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .and_return(instance_id_object)

      allow(telemetry_manager).to receive(:monitor)
        .with('detach_disk', id: instance_id).and_call_original
    end

    it 'detaches the disk from the vm' do
      old_settings = {
        'foo' => 'bar',
        'disks' => {
          'persistent' => {
            'fake-disk-id' =>  {
              'lun' => '1',
              'host_device_id' => host_device_id,
              'path' => '/dev/sdd'
            },
            'v-deadbeef' =>  {
              'lun'      => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      new_settings = {
        'foo' => 'bar',
        'disks' => {
          'persistent' => {
            'v-deadbeef' => {
              'lun' => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      expect(registry_client).to receive(:read_settings)
        .with(instance_id)
        .and_return(old_settings)
      expect(registry_client).to receive(:update_settings)
        .with(instance_id, new_settings)

      expect(vm_manager).to receive(:detach_disk).with(instance_id_object, disk_id_object)

      expect do
        cloud.detach_disk(instance_id, disk_id)
      end.not_to raise_error
    end
  end
end
