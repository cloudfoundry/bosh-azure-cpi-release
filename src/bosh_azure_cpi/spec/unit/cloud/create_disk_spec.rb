# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#create_disk' do
    let(:cloud_properties) { {} }
    let(:instance_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
    let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:vm_name) { 'fake-vm-name' }

    before do
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .and_return(instance_id_object)
      allow(instance_id_object).to receive(:resource_group_name)
        .and_return(resource_group_name)
      allow(instance_id_object).to receive(:vm_name)
        .and_return(vm_name)
      allow(telemetry_manager).to receive(:monitor)
        .with('create_disk', id: instance_id, extras: { 'disk_size' => disk_size })
        .and_call_original
    end

    context 'validating disk size' do
      context 'when disk size is not an integer' do
        let(:disk_size) { 1024.42 }

        it 'should raise an error' do
          expect do
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.to raise_error(
            ArgumentError,
            "The disk size needs to be an integer. The current value is '#{disk_size}'."
          )
        end
      end

      context 'when disk size is smaller than 1 GiB' do
        let(:disk_size) { 100 }

        it 'should raise an error' do
          expect do
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.to raise_error /Azure CPI minimum disk size is 1 GiB/
        end
      end
    end

    context 'validating caching' do
      context 'when caching is invalid in cloud_properties' do
        let(:disk_size) { 100 * 1024 }
        let(:cloud_properties) do
          {
            'caching' => 'Invalid'
          }
        end

        it 'should raise an error' do
          expect do
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.to raise_error /Unknown disk caching/
        end
      end
    end

    context 'when use_managed_disks is true' do
      let(:disk_size_in_gib) { 42 }
      let(:disk_size) { disk_size_in_gib * 1024 }
      let(:caching) { 'ReadOnly' }
      let(:cloud_properties) do
        {
          'caching' => caching
        }
      end

      context 'when instance_id is nil' do
        let(:instance_id) { nil }
        let(:rg_location) { 'fake-resource-group-location' }
        let(:resource_group) do
          {
            location: rg_location
          }
        end
        let(:zone) { nil }

        before do
          allow(azure_client).to receive(:get_resource_group).and_return(resource_group)
        end

        it 'should create a managed disk with the default location and storage account type' do
          expect(Bosh::AzureCloud::DiskId).to receive(:create)
            .with(caching, true, resource_group_name: default_resource_group_name)
            .and_return(disk_id_object)
          expect(disk_manager2).to receive(:create_disk)
            .with(disk_id_object, rg_location, disk_size_in_gib, 'Standard_LRS', zone)
          expect(telemetry_manager).to receive(:monitor)
            .with('create_disk', id: '', extras: { 'disk_size' => disk_size })
            .and_call_original

          expect do
            managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.not_to raise_error
        end
      end

      context 'when instance_id is not nil' do
        context 'when the instance is an unmanaged vm' do
          before do
            allow(instance_id_object).to receive(:use_managed_disks?)
              .and_return(false)
          end

          it "can't create a managed disk for a VM with unmanaged disks" do
            expect do
              managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
            end.to raise_error /Cannot create a managed disk for a VM with unmanaged disks/
          end
        end

        context 'when the instance is a managed vm' do
          let(:vm_location) { 'fake-vm-location' }
          let(:vm_zone) { 'fake-zone' }
          let(:vm) do
            {
              location: vm_location,
              vm_size: 'Standard_F1s',
              zone: vm_zone
            }
          end

          before do
            allow(instance_id_object).to receive(:use_managed_disks?)
              .and_return(true)
            allow(azure_client).to receive(:get_virtual_machine_by_name)
              .with(resource_group_name, vm_name)
              .and_return(vm)
          end

          context 'when storage_account_type is not specified' do
            it 'should create a managed disk in the same location with the vm and use the default storage account type' do
              expect(Bosh::AzureCloud::DiskId).to receive(:create)
                .with(caching, true, resource_group_name: resource_group_name)
                .and_return(disk_id_object)
              expect(disk_manager2).to receive(:create_disk)
                .with(disk_id_object, vm_location, disk_size_in_gib, 'Premium_LRS', vm_zone)

              expect do
                managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
              end.not_to raise_error
            end
          end

          context 'when storage_account_type is specified' do
            let(:cloud_properties) do
              {
                'caching' => caching,
                'storage_account_type' => 'Standard_LRS'
              }
            end
            it 'should create a managed disk in the same location with the vm and use the specified storage account type' do
              expect(Bosh::AzureCloud::DiskId).to receive(:create)
                .with(caching, true, resource_group_name: resource_group_name)
                .and_return(disk_id_object)
              expect(disk_manager2).to receive(:create_disk)
                .with(disk_id_object, vm_location, disk_size_in_gib, 'Standard_LRS', vm_zone)

              expect do
                managed_cloud.create_disk(disk_size, cloud_properties, instance_id)
              end.not_to raise_error
            end
          end
        end
      end
    end

    context 'when use_managed_disks is false' do
      let(:disk_size_in_gib) { 42 }
      let(:disk_size) { disk_size_in_gib * 1024 }
      let(:caching) { 'ReadOnly' }
      let(:storage_account_name) { 'fake-storage-account-name' }
      let(:cloud_properties) do
        {
          'caching' => caching
        }
      end

      context 'when instance_id is not nil' do
        let(:vm_storage_account_name) { 'vmstorageaccountname' }

        before do
          allow(instance_id_object).to receive(:storage_account_name)
            .and_return(vm_storage_account_name)
        end

        it 'should create an unmanaged disk in the same storage account of the vm' do
          expect(Bosh::AzureCloud::DiskId).to receive(:create)
            .with(caching, false, resource_group_name: MOCK_RESOURCE_GROUP_NAME, storage_account_name: vm_storage_account_name)
            .and_return(disk_id_object)
          expect(disk_manager).to receive(:create_disk)
            .with(disk_id_object, disk_size_in_gib)

          expect do
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.not_to raise_error
        end
      end

      context 'when instance_id is nil' do
        let(:instance_id) { nil }

        it 'should create an unmanaged disk in the default storage account of global configuration' do
          expect(Bosh::AzureCloud::DiskId).to receive(:create)
            .with(caching, false, resource_group_name: MOCK_RESOURCE_GROUP_NAME, storage_account_name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
            .and_return(disk_id_object)
          expect(disk_manager).to receive(:create_disk)
            .with(disk_id_object, disk_size_in_gib)
          expect(telemetry_manager).to receive(:monitor)
            .with('create_disk', id: '', extras: { 'disk_size' => disk_size })
            .and_call_original

          expect do
            cloud.create_disk(disk_size, cloud_properties, instance_id)
          end.not_to raise_error
        end
      end
    end
  end
end
