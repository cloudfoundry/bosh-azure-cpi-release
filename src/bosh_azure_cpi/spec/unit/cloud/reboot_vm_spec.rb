# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#reboot_vm' do
    let(:instance_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .with(instance_id, azure_properties)
        .and_return(instance_id_object)
      allow(telemetry_manager).to receive(:monitor)
        .with('reboot_vm', id: instance_id).and_call_original
    end

    it 'reboot an instance' do
      expect(vm_manager).to receive(:reboot).with(instance_id_object)

      expect do
        cloud.reboot_vm(instance_id)
      end.not_to raise_error
    end
  end
end
