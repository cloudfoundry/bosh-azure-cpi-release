# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#attach_disk' do
    let(:storage_account_name) { 'fakestorageaccountname' }
    let(:lun) { '1' }
    let(:host_device_id) { '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}' }
    let(:old_settings) { { 'foo' => 'bar' } }
    let(:new_settings) do
      {
        'foo' => 'bar',
        'disks' => {
          'persistent' => {
            disk_cid => {
              'lun' => lun,
              'host_device_id' => host_device_id
            }
          }
        }
      }
    end
    let(:disk_name) { 'fake-disk-name' }
    let(:disk_cid) { 'fake-disk-cid' }
    let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }

    let(:vm_name) { 'fake-vm-name' }
    let(:vm_cid) { 'fake-vm-cid' }
    let(:instance_id_object) { instance_double(Bosh::AzureCloud::InstanceId) }
    let(:vm) do
      {
        name: vm_name,
        data_disks: [
          {
            name: 'bosh-disk-os-fake-ephemeral-disk'
          }
        ]
      }
    end

    before do
      allow(Bosh::AzureCloud::DiskId).to receive(:parse)
        .with(disk_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(disk_id_object)
      allow(Bosh::AzureCloud::InstanceId).to receive(:parse)
        .with(vm_cid, MOCK_RESOURCE_GROUP_NAME)
        .and_return(instance_id_object)
      allow(instance_id_object).to receive(:to_s)
        .and_return(vm_cid)
      allow(disk_id_object).to receive(:to_s)
        .and_return(disk_cid)

      allow(disk_id_object).to receive(:disk_name)
        .and_return(disk_name)
      allow(instance_id_object).to receive(:vm_name)
        .and_return(vm_name)

      allow(vm_manager).to receive(:find)
        .and_return(vm)

      allow(telemetry_manager).to receive(:monitor)
        .with('attach_disk', { id: vm_cid }).and_call_original
    end

    context 'when the disk is a managed disk' do
      let(:disk) { {} }

      before do
        allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(disk)
      end

      context 'when the vm is a vm with managed disks' do
        context 'and disk exists' do
          it 'attaches the managed disk to the vm' do
            expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object)
                                                       .and_return(lun)

            expect do
              managed_cloud.attach_disk(vm_cid, disk_cid)
            end.not_to raise_error
          end
        end

        context 'and disk does not exist' do
          before do
            allow(disk_manager2).to receive(:get_data_disk).with(disk_id_object).and_return(nil)
            allow(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object)
                                                      .and_raise('disk not found')
          end

          it 'should not migrate the disk' do
            expect(disk_manager2).not_to receive(:create_disk_from_blob)

            expect do
              managed_cloud.attach_disk(vm_cid, disk_cid)
            end.to raise_error 'disk not found'
          end
        end
      end

      context 'when the vm is in a zone but the disk is not' do
        let(:disk) { {} }
        let(:vm_zone) { 'fake-zone' }

        before do
          vm[:zone] = vm_zone
          allow(vm_manager).to receive(:find)
            .and_return(vm)
        end

        context 'when the disk is migrated successfully' do
          before do
            allow(disk_manager2).to receive(:migrate_to_zone).with(disk_id_object, disk, vm_zone)
          end

          it 'attach the disk' do
            expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object)
                                                       .and_return(lun)

            expect do
              managed_cloud.attach_disk(vm_cid, disk_cid)
            end.not_to raise_error
          end
        end

        context 'when it fails to migrate the disk' do
          before do
            allow(disk_manager2).to receive(:migrate_to_zone)
              .and_raise(StandardError)
          end

          it 'raise an error' do
            expect do
              managed_cloud.attach_disk(vm_cid, disk_cid)
            end.to raise_error(/attach_disk - Failed to migrate disk/)
          end
        end
      end
    end

    # workaround for issue 280
    context 'when vm does not have an ephemeral disk' do
      before do
        vm[:data_disks] = []
        allow(instance_id_object).to receive(:vm_name)
          .and_return(vm_name)
      end

      it 'should sleep 30 seconds before attaching disk to the vm' do
        expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object)
                                                   .and_return(lun)
        expect(cloud).to receive(:sleep).with(30)

        expect do
          cloud.attach_disk(vm_cid, disk_cid)
        end.not_to raise_error
      end
    end

    it 'returns the disk hints' do
      expect(vm_manager).to receive(:attach_disk).with(instance_id_object, disk_id_object)
                                                .and_return(lun)
      result = cloud_v2.attach_disk(vm_cid, disk_cid)
      expect(result).to eq({ 'lun' => lun, 'host_device_id' => host_device_id })
    end
  end
end
