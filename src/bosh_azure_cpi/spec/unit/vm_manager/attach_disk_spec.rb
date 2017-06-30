require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe "#attach_disk" do
    let(:registry_endpoint) { mock_registry.endpoint }
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
    let(:azure_properties) { mock_azure_properties }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, disk_manager2, client2) }

    let(:caching) { "fake-caching" }
    let(:lun) { 1 }
    let(:vm_resource_group_name) { "fake-vm-resource-group-name" }
    let(:disk_resource_group_name) { "fake-disk-resource-group-name" }
    let(:storage_account_name) { "fake-storage-account-name" }

    let(:vm_name) { "fake-vm-name" }
    let(:disk_name) { "bosh-data-#{storage_account_name}-fake-disk-name-#{caching}" }
    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
    let(:disk_id) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:disk_id_string) { "fake-disk-id" }

    before do
      allow(instance_id).to receive(:resource_group_name).
        and_return(vm_resource_group_name)
      allow(instance_id).to receive(:vm_name).
        and_return(vm_name)

      allow(disk_id).to receive(:resource_group_name).
        and_return(disk_resource_group_name)
      allow(disk_id).to receive(:disk_name).
        and_return(disk_name)
      allow(disk_id).to receive(:caching).
        and_return(caching)
      allow(disk_id).to receive(:to_s).
        and_return(disk_id_string)
    end

    context "When the disk is unmanaged disk" do
      let(:disk_uri) { "fake-disk-uri" }
      let(:disk_size) { 42 }
      let(:disk_params) {
        {
          :disk_name     => disk_name,
          :caching       => caching,
          :disk_uri      => disk_uri,
          :disk_size     => disk_size,
          :managed       => false,
          :disk_bosh_id  => disk_id_string
        }
      }

      before do
        allow(instance_id).to receive(:use_managed_disks?).
          and_return(false)
        allow(disk_manager).to receive(:get_data_disk_uri).
          with(disk_id).and_return(disk_uri)
        allow(disk_manager).to receive(:get_disk_size_in_gb).
          with(disk_id).and_return(disk_size)
      end

      it "attaches the disk to an instance" do
        expect(client2).to receive(:attach_disk_to_virtual_machine).
          with(vm_resource_group_name, vm_name, disk_params).
          and_return(lun)
        expect(vm_manager.attach_disk(instance_id, disk_id)).to eq("#{lun}")
      end
    end

    context "When the disk is managed disk" do
      let(:managed_disk_id) { "fake-id" }
      let(:managed_disk) { {:id => managed_disk_id} }
      let(:disk_params) {
        {
          :disk_name     => disk_name,
          :caching       => caching,
          :disk_id       => managed_disk_id,
          :managed       => true,
          :disk_bosh_id  => disk_id_string
        }
      }

      before do
        allow(instance_id).to receive(:use_managed_disks?).
          and_return(true)
        allow(client2).to receive(:get_managed_disk_by_name).
          with(disk_resource_group_name, disk_name).
          and_return(managed_disk)
      end

      it "attaches the disk to an instance" do
        expect(client2).to receive(:attach_disk_to_virtual_machine).
          with(vm_resource_group_name, vm_name, disk_params).
          and_return(lun)
        expect(vm_manager.attach_disk(instance_id, disk_id)).to eq("#{lun}")
      end
    end
  end
end
