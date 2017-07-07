require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe "#find" do
    let(:registry_endpoint) { mock_registry.endpoint }
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
    let(:azure_properties) { mock_azure_properties }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, disk_manager2, client2) }

    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }

    let(:vm_name) { "fake-vm-name" }
    let(:resource_group_name) { "fake-resource-group-name" }

    before do
      allow(instance_id).to receive(:resource_group_name).
        and_return(resource_group_name)
      allow(instance_id).to receive(:vm_name).
        and_return(vm_name)
    end

    context "when everything is ok" do
      it "finds the instance by id" do
        expect(client2).to receive(:get_virtual_machine_by_name).
          with(resource_group_name, vm_name)
        expect {
          vm_manager.find(instance_id)
        }.not_to raise_error
      end
    end
  end
end
