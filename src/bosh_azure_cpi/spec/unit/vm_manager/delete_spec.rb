require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe "#delete" do
    let(:registry_endpoint) { mock_registry.endpoint }
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
    let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
    let(:azure_properties) { mock_azure_properties }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager) }

    let(:resource_group_name) { "fake-resource-group-name" }
    let(:storage_account_name) { "fake-storage-account-name" }
    let(:vm_name) { "fake-vm-name" }
    let(:availability_set_name) { "#{SecureRandom.uuid}" }

    let(:load_balancer) { double("load_balancer") }
    let(:network_interface) {
      {
        :tags => {}
      }
    }
    let(:os_disk_name) { "fake-os-disk-name" }
    let(:ephemeral_disk_name) { "fake-ephemeral-disk-name" }
    let(:public_ip) { "fake-public-ip" }

    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(instance_id).to receive(:resource_group_name).
        and_return(resource_group_name)
      allow(instance_id).to receive(:vm_name).
        and_return(vm_name)

      allow(client2).to receive(:get_load_balancer_by_name).
        with(vm_name).and_return(load_balancer)
      allow(client2).to receive(:get_network_interface_by_name).
        with(resource_group_name, vm_name).and_return(network_interface)
      allow(client2).to receive(:get_public_ip_by_name).
        with(resource_group_name, vm_name).and_return(public_ip)
    end

    context "When vm is not nil" do
      before do
        # It does NOT matter whether the vm is with managed disk or not. We assume the vm is with managed disks.
        allow(instance_id).to receive(:use_managed_disks?).
          and_return(true)
        allow(disk_manager2).to receive(:generate_os_disk_name).
          with(vm_name).
          and_return(os_disk_name)
        allow(disk_manager2).to receive(:generate_ephemeral_disk_name).
          with(vm_name).
          and_return(ephemeral_disk_name)
      end

      context "when vm is not in an availability set" do
        let(:vm) {
          {
             :network_interfaces => [
               {:name => "fake-nic-1"},
               {:name => "fake-nic-2"}
             ]
          }
        }
        before do
          allow(client2).to receive(:get_virtual_machine_by_name).
            with(resource_group_name, vm_name).and_return(vm)
        end

        it "should delete all resources" do
          expect(client2).to receive(:delete_virtual_machine).with(resource_group_name, vm_name)
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-1")
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-2")
          expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)
          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name)
          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

          expect {
            vm_manager.delete(instance_id)
          }.not_to raise_error
        end
      end

      context "when vm is in an availability set" do
        let(:rwlock) { instance_double(Bosh::AzureCloud::Helpers::ReadersWriterLock) }
        before do
          allow(Bosh::AzureCloud::Helpers::ReadersWriterLock).to receive(:new).and_return(rwlock)
          allow(rwlock).to receive(:acquire_write_lock).and_return(true)
          allow(rwlock).to receive(:release_write_lock)
        end

        context "when the availability set contains VMs" do
          let(:availability_set) {
            {
              :name => availability_set_name,
              :virtual_machines => [
                "fake-vm-id-1",
                "fake-vm-id-2"
              ]
            }
          }
          let(:vm) {
            {
               :availability_set => availability_set,
               :network_interfaces => [
                 {:name => "fake-nic-1"},
                 {:name => "fake-nic-2"}
               ]
            }
          }
          before do
            allow(client2).to receive(:get_virtual_machine_by_name).
              with(resource_group_name, vm_name).and_return(vm)
            allow(client2).to receive(:get_availability_set_by_name).
              with(resource_group_name, availability_set_name).and_return(availability_set)
          end

          it "should delete all resources, not including the availability set" do
            expect(client2).to receive(:delete_virtual_machine).with(resource_group_name, vm_name)
            expect(client2).not_to receive(:delete_availability_set)
            expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-1")
            expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-2")
            expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name)
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

            expect {
              vm_manager.delete(instance_id)
            }.not_to raise_error
          end
        end

        context "when the availability set contains no VMs" do
          let(:availability_set) {
            {
              :name => availability_set_name,
              :virtual_machines => []
            }
          }
          let(:vm) {
            {
               :availability_set => availability_set,
               :network_interfaces => [
                 {:name => "fake-nic-1"},
                 {:name => "fake-nic-2"}
               ]
            }
          }
          before do
            allow(client2).to receive(:get_virtual_machine_by_name).
              with(resource_group_name, vm_name).and_return(vm)
            allow(client2).to receive(:get_availability_set_by_name).
              with(resource_group_name, availability_set_name).and_return(availability_set)
          end

          it "should delete all resources, including the availability set" do
            expect(client2).to receive(:delete_virtual_machine).with(resource_group_name, vm_name)
            expect(client2).to receive(:delete_availability_set).with(resource_group_name, availability_set_name)
            expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-1")
            expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-2")
            expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name)
            expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

            expect {
              vm_manager.delete(instance_id)
            }.not_to raise_error
          end

          context "when it fails to delete the availability set" do
            it "raises an error" do
              expect(client2).to receive(:delete_virtual_machine).with(resource_group_name, vm_name)
              expect(client2).to receive(:delete_availability_set).and_raise(StandardError)
              expect(client2).not_to receive(:delete_network_interface).with(resource_group_name, "fake-nic-1")
              expect(client2).not_to receive(:delete_network_interface).with(resource_group_name, "fake-nic-2")
              expect(client2).not_to receive(:delete_public_ip).with(resource_group_name, vm_name)
              expect(disk_manager2).not_to receive(:delete_disk).with(resource_group_name, os_disk_name)
              expect(disk_manager2).not_to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

              expect {
                vm_manager.delete(instance_id)
              }.to raise_error(StandardError)
            end
          end
        end
      end
    end

    context "When vm is nil" do
      before do
        # It does NOT matter whether the vm is with managed disk or not. We assume the vm is with managed disks.
        allow(instance_id).to receive(:use_managed_disks?).
          and_return(true)
        allow(disk_manager2).to receive(:generate_os_disk_name).
          with(vm_name).
          and_return(os_disk_name)
        allow(disk_manager2).to receive(:generate_ephemeral_disk_name).
          with(vm_name).
          and_return(ephemeral_disk_name)
      end

      context "When the tags of network interfaces don't include availability set name" do
        let(:network_interfaces) {
          [
            {
              :name => "fake-possible-nic-1",
              :tags => {}
            },
            {
              :name => "fake-possible-nic-2",
              :tags => {}
            }
          ]
        }

        before do
          allow(client2).to receive(:get_virtual_machine_by_name).
            with(resource_group_name, vm_name).and_return(nil)
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).and_return(network_interfaces)
        end

        it "should delete other resources but not delete the vm and the availability set" do
          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_availability_set)
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-possible-nic-1")
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-possible-nic-2")
          expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)

          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name)
          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

          expect {
            vm_manager.delete(instance_id)
          }.not_to raise_error
        end
      end

      context "When the tags of network interfaces include availability set name" do
        let(:network_interfaces) {
          [
            {
              :name => "fake-possible-nic-1",
              :tags => {
                "availability_set" => availability_set_name
              }
            },
            {
              :name => "fake-possible-nic-2",
              :tags => {}
            }
          ]
        }
        let(:availability_set) {
          {
            :name => availability_set_name,
            :virtual_machines => []
          }
        }

        before do
          allow(client2).to receive(:get_virtual_machine_by_name).
            with(resource_group_name, vm_name).and_return(nil)
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).and_return(network_interfaces)
          allow(client2).to receive(:get_availability_set_by_name).
            with(resource_group_name, availability_set_name).and_return(availability_set)
        end

        let(:rwlock) { instance_double(Bosh::AzureCloud::Helpers::ReadersWriterLock) }
        before do
          allow(Bosh::AzureCloud::Helpers::ReadersWriterLock).to receive(:new).and_return(rwlock)
          allow(rwlock).to receive(:acquire_write_lock).and_return(true)
          allow(rwlock).to receive(:release_write_lock)
        end

        it "should delete other resources and the availability set but not delete the vm" do
          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).to receive(:delete_availability_set).with(resource_group_name, availability_set_name).once
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-possible-nic-1")
          expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-possible-nic-2")
          expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)

          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, os_disk_name)
          expect(disk_manager2).to receive(:delete_disk).with(resource_group_name, ephemeral_disk_name)

          expect {
            vm_manager.delete(instance_id)
          }.not_to raise_error
        end
      end
    end

    context "When vm is with unmanaged disk" do
      before do
        allow(instance_id).to receive(:use_managed_disks?).
          and_return(false)
        allow(instance_id).to receive(:storage_account_name).
          and_return(storage_account_name)
        allow(disk_manager).to receive(:generate_os_disk_name).
          with(vm_name).
          and_return(os_disk_name)
        allow(disk_manager).to receive(:generate_ephemeral_disk_name).
          with(vm_name).
          and_return(ephemeral_disk_name)
      end

      # It does NOT matter whether the vm is nil or not. We assume that vm is not nil.
      let(:vm) {
        {
           :network_interfaces => [
             {:name => "fake-nic-1"},
             {:name => "fake-nic-2"}
           ]
        }
      }
      before do
        allow(client2).to receive(:get_virtual_machine_by_name).
          with(resource_group_name, vm_name).and_return(vm)
      end

      it "should delete all resources" do
        expect(client2).to receive(:delete_virtual_machine).with(resource_group_name, vm_name)
        expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-1")
        expect(client2).to receive(:delete_network_interface).with(resource_group_name, "fake-nic-2")
        expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)
        expect(disk_manager).to receive(:delete_disk).with(storage_account_name, os_disk_name)
        expect(disk_manager).to receive(:delete_disk).with(storage_account_name, ephemeral_disk_name)
        expect(disk_manager).to receive(:delete_vm_status_files).
          with(storage_account_name, vm_name)

        expect {
          vm_manager.delete(instance_id)
        }.not_to raise_error
      end
    end
  end
end
