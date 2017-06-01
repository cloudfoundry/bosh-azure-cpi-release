require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#create_disk' do
    let(:cloud_properties) { {} }
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    context 'validating disk size' do
      context 'when disk size is not an integer' do
        let(:disk_size) { 1024.42 }

        it 'should raise an error' do
          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.to raise_error(
            ArgumentError,
            'disk size needs to be an integer'
          )
        end
      end

      context 'when disk size is smaller than 1 GiB' do
        let(:disk_size) { 100 }

        it 'should raise an error' do
          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.to raise_error /Azure CPI minimum disk size is 1 GiB/
        end
      end

      context 'when disk size is larger than 1023 GiB' do
        let(:disk_size) { 1024 * 1024 }

        it 'should raise an error' do
          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.to raise_error /Azure CPI maximum disk size is 1023 GiB/
        end
      end
    end

    context "validating caching" do
      context "when caching is invalid in cloud_properties" do
        let(:disk_size) { 100 * 1024 }
        let(:cloud_properties) {
          {
            "caching" => "Invalid"
          }
        }

        it "should raise an error" do
          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.to raise_error /Unknown disk caching/
        end
      end
    end

    context "when use_managed_disks is true" do
      let(:disk_size_in_gib) { 42 }
      let(:disk_size) { disk_size_in_gib * 1024 }
      let(:caching) { "ReadOnly" }
      let(:cloud_properties) {
        {
          "caching" => caching
        }
      }

      context "when instance_id is nil" do
        let(:instance_id) { nil }
        let(:rg_location) { "fake-resource-group-location" }
        let(:resource_group) {
          {
            :location => rg_location
          }
        }

        before do
          allow(client2).to receive(:get_resource_group).and_return(resource_group)
        end

        it "should create a managed disk with the default location and storage account type" do
          expect(disk_manager2).to receive(:create_disk).with(rg_location, disk_size_in_gib, "Standard_LRS", caching)

          expect {
            managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.not_to raise_error
        end
      end

      context "when instance_id is not nil" do
        context "when the instance is an unmanaged vm" do
          let(:instance_id) { "fake-instance-id" }

          it "can't create a managed disk for a VM with unmanaged disks" do
            expect {
              managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
            }.to raise_error /Cannot create a managed disk for a VM with unmanaged disks/ 
          end
        end

        context "when the instance is a managed vm" do
          let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
          let(:vm_location) { "fake-vm-location" }
          let(:vm) {
            {
              :location => vm_location,
              :vm_size => "Standard_F1s"
            }
          }

          before do
            allow(client2).to receive(:get_virtual_machine_by_name).with(instance_id).and_return(vm)
          end

          context "when storage_account_type is not specified" do
            it "should create a managed disk in the same location with the vm and use the default storage account type" do
              expect(disk_manager2).to receive(:create_disk).with(vm_location, disk_size_in_gib, "Premium_LRS", caching)

              expect {
                managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
              }.not_to raise_error
            end
          end

          context "when storage_account_type is specified" do
            let(:cloud_properties) {
              {
                "caching" => caching,
                "storage_account_type" => "Standard_LRS"
              }
            }
            it "should create a managed disk in the same location with the vm and use the specified storage account type" do
              expect(disk_manager2).to receive(:create_disk).with(vm_location, disk_size_in_gib, "Standard_LRS", caching)

              expect {
                managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
              }.not_to raise_error
            end
          end
        end
      end
    end

    context "when use_managed_disks is false" do
      let(:disk_size_in_gib) { 42 }
      let(:disk_size) { disk_size_in_gib * 1024 }
      let(:caching) { "ReadOnly" }
      let(:storage_account_name) { "fake-storage-account-name" }
      let(:cloud_properties) {
        {
          "caching" => caching
        }
      }

      context "when instance_id is not nil" do
        let(:vm_storage_account_name) { "vmstorageaccountname" }
        let(:instance_id)  { "#{vm_storage_account_name}-guid" }

        it "should create an unmanaged disk in the same storage account of the vm" do
          expect(disk_manager).to receive(:create_disk).with(disk_size_in_gib, vm_storage_account_name, caching)

          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.not_to raise_error
        end
      end

      context "when instance_id is nil" do
        let(:instance_id) { nil }

        it "should create an unmanaged disk in the default storage account of global configuration" do
          expect(disk_manager).to receive(:create_disk).with(disk_size_in_gib, MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, caching)

          expect {
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          }.not_to raise_error
        end
      end
    end
  end
end
