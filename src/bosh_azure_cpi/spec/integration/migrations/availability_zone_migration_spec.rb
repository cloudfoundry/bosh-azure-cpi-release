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
    described_class.new(@cloud_options.dup, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  subject(:cpi_managed_v1) do
    described_class.new(@cloud_options.dup, 1)
  end

  before { @disk_id_pool = [] }

  after do
    @disk_id_pool.each do |disk_id|
      @logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      cpi_managed.delete_disk(disk_id) if disk_id
    end
  end

  context 'Migrate regional VM to zonal VM', availability_zone: true, migration: true do
    context 'when the regional VM is with managed disks' do
      let(:disk_id) { cpi_managed.create_disk(2048, {}, nil) }

      before do
        # Create an regional disk
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
