# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#set_vm_metadata' do
    let(:vm_cid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .with(vm_cid, azure_config.resource_group_name)
        .and_return(instance_id_object)
      allow(telemetry_manager).to receive(:monitor)
        .with('set_vm_metadata', id: vm_cid).and_call_original
    end

    context 'when the metadata is not encoded' do
      let(:metadata) { { 'user-agent' => 'bosh' } }

      it 'should set the vm metadata' do
        expect(vm_manager).to receive(:set_metadata).with(instance_id_object, metadata)

        expect do
          cloud.set_vm_metadata(vm_cid, metadata)
        end.not_to raise_error
      end
    end

    context 'when the metadata is encoded' do
      let(:metadata) do
        {
          'user-agent' => 'bosh',
          'foo' => 42 # The value doesn't matter. It's an integer.
        }
      end
      let(:encoded_metadata) do
        {
          'user-agent' => 'bosh',
          'foo' => '42'
        }
      end

      it 'should set the vm metadata' do
        expect(vm_manager).to receive(:set_metadata).with(instance_id_object, encoded_metadata)

        expect do
          cloud.set_vm_metadata(vm_cid, metadata)
        end.not_to raise_error
      end
    end
  end
end
