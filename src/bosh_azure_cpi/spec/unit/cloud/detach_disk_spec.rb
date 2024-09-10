# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#detach_disk' do
    let(:vm_cid) { 'fake-vm-cid' }
    let(:disk_cid) { 'fake-disk-cid' }
    let(:host_device_id) { 'fake-host-device-id' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .with(disk_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(disk_id_object)
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .with(vm_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(instance_id_object)
      allow(telemetry_manager).to receive(:monitor)
        .with('detach_disk', { id: vm_cid }).and_call_original
    end

    it 'detaches the disk from the vm' do
      expect(vm_manager).to receive(:detach_disk).with(instance_id_object, disk_id_object)

      expect do
        cloud.detach_disk(vm_cid, disk_cid)
      end.not_to raise_error
    end
  end
end
