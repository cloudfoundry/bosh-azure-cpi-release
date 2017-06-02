require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#delete_vm" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    it 'should delete an instance' do
      expect(vm_manager).to receive(:delete).with(instance_id)

      expect {
        cloud.delete_vm(instance_id)
      }.not_to raise_error
    end
  end
end
