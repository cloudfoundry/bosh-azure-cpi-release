require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#attach_disk" do
    let(:storage_account_name) { "fakestorageaccountname" }
    let(:lun) { '1' }
    let(:volume_name) { '/dev/sdd' }
    let(:host_device_id) { '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}' }
    let(:old_settings) { { 'foo' => 'bar'} }
    let(:new_settings) {
      {
        'foo' => 'bar',
        'disks' => {
          'persistent' => {
            disk_id => {
              'lun' => lun,
              'host_device_id' => host_device_id,
              'path' => volume_name
            }
          }
        }
      }
    }
    let(:disk_name) { "fake-disk-name" }
    let(:disk_id) { "fake-disk-id" }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }

    let(:vm_name) { "fake-vm-name" }
    let(:instance_id)  { "fake-instance-id" }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse).
        and_return(disk_id_object)
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse).
        and_return(instance_id_object)
      allow(instance_id_object).to receive(:to_s).
        and_return(instance_id)
      allow(disk_id_object).to receive(:to_s).
        and_return(disk_id)

      allow(disk_id_object).to receive(:disk_name).
        and_return(disk_name)
      allow(instance_id_object).to receive(:vm_name).
        and_return(vm_name)
    end

    context "when use_managed_disks is true" do
      context "when the disk is a managed disk" do
        let(:disk) { double("disk") }
        before do
          allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(disk)
        end

        context "when the vm is a vm with managed disks" do
          before do
            allow(instance_id_object).to receive(:use_managed_disks?).
              and_return(true)
          end

          it "attaches the managed disk to the vm" do
            expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object).
              and_return(lun)
            expect(registry).to receive(:read_settings).with(instance_id).
              and_return(old_settings)
            expect(registry).to receive(:update_settings).
              with(instance_id, new_settings).and_return(true)

            expect {
              managed_cloud.attach_disk(instance_id, disk_id)
            }.not_to raise_error
          end
        end

        context "when the vm is a vm with unmanaged disks" do
          before do
            allow(instance_id_object).to receive(:use_managed_disks?).
              and_return(false)
          end

          it "can't attach a managed disk to a VM with unmanaged disks" do
            expect {
              managed_cloud.attach_disk(instance_id, disk_id)
            }.to raise_error /Cannot attach a managed disk to a VM with unmanaged disks/
          end
        end
      end

      context "when the disk is an unmanaged disk" do
        before do
          allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(nil)
        end

        context "when the vm is a vm with managed disks" do
          let(:blob_uri) { "fake-blob-uri" }
          let(:location) { "fake-location" }
          let(:account_type) { "Premium_LRS" }
          let(:storage_account) {
            {
              :location => location,
              :account_type => account_type
            }
          }

          before do
            allow(instance_id_object).to receive(:use_managed_disks?).
              and_return(true)
            allow(disk_manager).to receive(:get_data_disk_uri).
              with(disk_id_object).
              and_return(blob_uri)
            allow(client2).to receive(:get_storage_account_by_name).
              with(storage_account_name).
              and_return(storage_account)
          end

          context "a managed disk is created successfully from the unmanage disk" do
            it "attaches the managed disk to the vm" do
              expect(disk_id_object).to receive(:storage_account_name).
                and_return(storage_account_name)
              expect(disk_manager2).to receive(:create_disk_from_blob).
                with(disk_id_object, blob_uri, location, account_type)
              expect(blob_manager).to receive(:set_blob_metadata)

              expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object).
                and_return(lun)
              expect(registry).to receive(:read_settings).with(instance_id).
                and_return(old_settings)
              expect(registry).to receive(:update_settings).
                with(instance_id, new_settings).and_return(true)

              expect {
                managed_cloud.attach_disk(instance_id, disk_id)
              }.not_to raise_error
            end
          end

          context "a managed disk fails to be created from the unmanage disk" do
            before do
              allow(disk_manager2).to receive(:create_disk_from_blob).and_raise(StandardError)
              allow(disk_id_object).to receive(:storage_account_name).
                and_return(storage_account_name)
            end

            context "the managed disk is cleaned up" do
              before do
                allow(disk_manager2).to receive(:delete_data_disk).with(disk_id_object)
              end

              it "fails to attach the managed disk to the vm, but successfully cleanup the managed disk" do
                expect(blob_manager).not_to receive(:set_blob_metadata)

                expect {
                  managed_cloud.attach_disk(instance_id, disk_id)
                }.to raise_error /attach_disk - Failed to create the managed disk/
              end
            end

            context "the managed disk is not cleaned up" do
              before do
                allow(disk_manager2).to receive(:delete_data_disk).with(disk_id_object).and_raise(StandardError)
              end

              it "fails to attach the managed disk to the vm and cleanup the managed disk" do
                expect(blob_manager).not_to receive(:set_blob_metadata)

                expect {
                  managed_cloud.attach_disk(instance_id, disk_id)
                }.to raise_error /attach_disk - Failed to create the managed disk/
              end
            end
          end
        end

        context "when the vm is a vm with unmanaged disks" do
          before do
            allow(instance_id_object).to receive(:use_managed_disks?).
              and_return(false)
          end

          it "attaches the unmanaged disk to the vm" do
            expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object).
              and_return(lun)
            expect(registry).to receive(:read_settings).with(instance_id).
              and_return(old_settings)
            expect(registry).to receive(:update_settings).
              with(instance_id, new_settings).and_return(true)

            expect {
              cloud.attach_disk(instance_id, disk_id)
            }.not_to raise_error
          end
        end
      end
    end

    context "when use_managed_disks is false" do
      it "attaches the unmanaged disk to the vm" do
        expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object).
          and_return(lun)
        expect(registry).to receive(:read_settings).with(instance_id).
          and_return(old_settings)
        expect(registry).to receive(:update_settings).
          with(instance_id, new_settings).and_return(true)

        expect {
          cloud.attach_disk(instance_id, disk_id)
        }.not_to raise_error
      end
    end
  end
end
