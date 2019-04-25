# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @additional_resource_group_name = ENV.fetch('BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME')
  end

  let(:network_spec) do
    {
      'network_a' => {
        'type' => 'dynamic',
        'cloud_properties' => {
          'virtual_network_name' => @vnet_name,
          'subnet_name' => @subnet_name
        }
      }
    }
  end
  let(:availability_zone) { Random.rand(1..3).to_s }
  let(:vm_properties) do
    {
      'instance_type' => @instance_type,
      'resource_group_name' => @additional_resource_group_name,
      'assign_dynamic_public_ip' => true,
      'availability_zone' => availability_zone
    }
  end

  subject(:cpi_managed) do
    cloud_options_managed = @cloud_options.dup
    cloud_options_managed['azure']['use_managed_disks'] = true
    described_class.new(cloud_options_managed, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  subject(:cpi_unmanaged) do
    cloud_options_unmanaged = @cloud_options.dup
    cloud_options_unmanaged['azure']['use_managed_disks'] = false
    described_class.new(cloud_options_unmanaged, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  subject(:cpi_managed_v1) do
    cloud_options_unmanaged = @cloud_options.dup
    cloud_options_unmanaged['azure']['use_managed_disks'] = true
    described_class.new(cloud_options_unmanaged, 1)
  end

  before { @disk_id_pool = [] }
  after do
    @disk_id_pool.each do |disk_id|
      @logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      cpi_managed.delete_disk(disk_id) if disk_id
    end
  end

  context 'Migrate regional VM to zonal VM', availability_zone: true, migration: true do
    context 'when the regional VM is with unmanaged disks' do
      before do
        # Create an unmanaged disk
        disk_id = cpi_unmanaged.create_disk(2048, {}, nil)
        expect(disk_id).not_to be_nil
        @disk_id_pool.push(disk_id)
      end

      after do
        # Delete the zonal disk, and the migrated unmanaged regional disk
        cpi_managed.delete_disk(disk_id)
        cpi_unmanaged.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end

      it 'should exercise the vm lifecycle' do
        vm_lifecycle(cpi: cpi_managed) do |instance_id|
          # Migrate the unmanaged regional disk to a managed zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
          @cpi.attach_disk(instance_id, disk_id)

          # Detach the zonal disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            @cpi.detach_disk(instance_id, disk_id)
            true
          end
        end
      end

      context 'when using v1 CPI' do
        it 'should still exercise the vm lifecycle' do
          vm_lifecycle(cpi: cpi_managed_v1) do |instance_id|
            # Migrate the unmanaged regional disk to a managed zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
            @cpi.attach_disk(instance_id, disk_id)

            # Detach the zonal disk
            Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
              @cpi.detach_disk(instance_id, disk_id)
              true
            end
          end
        end
      end
    end

    context 'when the regional VM is with managed disks' do
      before do
        # Create an regional disk
        disk_id = cpi_managed.create_disk(2048, {}, nil)
        expect(disk_id).not_to be_nil
        @disk_id_pool.push(disk_id)
      end

      after do
        # Delete the zonal disk
        cpi_managed.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end

      it 'should exercise the vm lifecycle' do
        vm_lifecycle(cpi: cpi_managed) do |instance_id|
          # Migrate the unmanaged regional disk to a managed zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
          @cpi.attach_disk(instance_id, disk_id)

          # Detach the zonal disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            @cpi.detach_disk(instance_id, disk_id)
            true
          end
        end
      end

      context 'when using v1 CPI' do
        it 'should still exercise the vm lifecycle' do
          vm_lifecycle(cpi: cpi_managed_v1) do |instance_id|
            # Migrate the unmanaged regional disk to a managed zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
            @cpi.attach_disk(instance_id, disk_id)

            # Detach the zonal disk
            Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
              @cpi.detach_disk(instance_id, disk_id)
              true
            end
          end
        end
      end
    end
  end
end
