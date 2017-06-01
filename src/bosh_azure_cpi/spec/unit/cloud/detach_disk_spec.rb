require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#detach_disk" do
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:disk_id) { "fake-disk-id" }
    let(:host_device_id) { 'fake-host-device-id' }
  
    it 'detaches the disk from the vm' do
      old_settings = {
        "foo" => "bar",
        "disks" => {
          "persistent" => {
            "fake-disk-id" =>  {
              'lun'      => '1',
              'host_device_id' => host_device_id,
              'path' => '/dev/sdd'
            },
            "v-deadbeef" =>  {
              'lun'      => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      new_settings = {
        "foo" => "bar",
        "disks" => {
          "persistent" => {
            "v-deadbeef" => {
              'lun' => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      expect(registry).to receive(:read_settings).
        with(instance_id).
        and_return(old_settings)
      expect(registry).to receive(:update_settings).
        with(instance_id, new_settings)

      expect(vm_manager).to receive(:detach_disk).with(instance_id, disk_id)

      expect {
        cloud.detach_disk(instance_id, disk_id)
      }.not_to raise_error
    end
  end
end
