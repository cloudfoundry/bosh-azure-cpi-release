require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#reboot_vm" do
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    it 'reboot an instance' do
      expect(vm_manager).to receive(:reboot).with(instance_id)

      expect {
        cloud.reboot_vm(instance_id)
      }.not_to raise_error
    end
  end
end
