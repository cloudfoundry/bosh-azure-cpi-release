# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#reboot_vm' do
    before do
      allow(Bosh::AzureCloud::CloudIdParser).to receive(:parse)
        .with(vm_cid, azure_config.resource_group_name)
        .and_return(instance_id_object)
      allow(telemetry_manager).to receive(:monitor)
        .with('reboot_vm', id: vm_cid).and_call_original
    end

    it 'reboot an instance' do
      expect(vm_manager).to receive(:reboot).with(instance_id_object)

      expect do
        cloud.reboot_vm(vm_cid)
      end.not_to raise_error
    end
  end
end
