require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#has_vm?' do
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }
    let(:instance) { double("instance") }

    before do
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse).
        with(instance_id, azure_properties).
        and_return(instance_id_object)
    end

    context "when the instance exists" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id_object).
          and_return(instance)
        allow(instance).to receive(:[]).with(:provisioning_state).
          and_return('Running')
      end

      it "should return true" do
        expect(cloud.has_vm?(instance_id)).to be(true)
      end
    end

    context "when the instance doesn't exists" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id_object).and_return(nil)
      end

      it "should return false" do
        expect(cloud.has_vm?(instance_id)).to be(false)
      end
    end

    context "when the instance state is Deleting" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id_object).
          and_return(instance)
        allow(instance).to receive(:[]).with(:provisioning_state).
          and_return('Deleting')
      end

      it 'should return false' do
        expect(cloud.has_vm?(instance_id)).to be(false)
      end
    end
  end
end
