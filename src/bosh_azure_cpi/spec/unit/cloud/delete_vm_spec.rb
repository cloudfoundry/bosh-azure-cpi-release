# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#delete_vm' do
    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('delete_vm', id: instance_id).and_call_original
    end

    it 'should delete an instance' do
      expect(Bosh::AzureCloud::InstanceIdParser).to receive(:parse)
        .with(instance_id, azure_config.resource_group_name)
        .and_return(instance_id_object)

      expect(vm_manager).to receive(:delete).with(instance_id_object)

      expect do
        cloud.delete_vm(instance_id)
      end.not_to raise_error
    end
  end
end
