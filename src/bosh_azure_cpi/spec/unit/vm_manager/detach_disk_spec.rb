require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe "#detach_disk" do
    let(:registry_endpoint) { mock_registry.endpoint }
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
    let(:azure_properties) { mock_azure_properties }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, disk_manager2, client2) }

    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
    let(:disk_id) { instance_double(Bosh::AzureCloud::DiskId) }

    let(:vm_name) { "fake-vm-name" }
    let(:resource_group_name) { "fake-resource-group-name" }
    let(:disk_name) { "fake-disk-name" }

    before do
      allow(instance_id).to receive(:resource_group_name).
        and_return(resource_group_name)
      allow(instance_id).to receive(:vm_name).
        and_return(vm_name)

      allow(disk_id).to receive(:disk_name).
        and_return(disk_name)
    end

    context "when everything is ok" do
      it "detach_disks the instance by id" do
        expect(client2).to receive(:detach_disk_from_virtual_machine).
          with(resource_group_name, vm_name, disk_name)
        expect {
          vm_manager.detach_disk(instance_id, disk_id)
        }.not_to raise_error
      end
    end
  end
end
