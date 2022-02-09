# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before { @disk_id_pool = [] }

  after do
    @disk_id_pool.each do |disk_id|
      @logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      @cpi.delete_disk(disk_id) if disk_id
    end
  end

  context 'when availability zone is specified', availability_zone: true do
    let(:availability_zone) { Random.rand(1..3).to_s }
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
    let(:vm_properties) do
      {
        'instance_type' => @instance_type,
        'availability_zone' => availability_zone,
        'assign_dynamic_public_ip' => true
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
        vm = get_azure_client.get_virtual_machine_by_name(@default_resource_group_name, instance_id_obj.vm_name)
        dynamic_public_ip = get_azure_client.get_public_ip_by_name(@default_resource_group_name, instance_id_obj.vm_name)
        expect(vm[:zone]).to eq(availability_zone)
        expect(dynamic_public_ip[:zone]).to eq(availability_zone)

        disk_id = @cpi.create_disk(2048, {}, instance_id)
        expect(disk_id).not_to be_nil
        disk_id_obj = Bosh::AzureCloud::DiskId.parse(disk_id, @azure_config.resource_group_name)
        disk = get_azure_client.get_managed_disk_by_name(@default_resource_group_name, disk_id_obj.disk_name)
        expect(disk[:zone]).to eq(availability_zone)
        @disk_id_pool.push(disk_id)

        @cpi.attach_disk(instance_id, disk_id)

        snapshot_metadata = @vm_metadata.merge(
          bosh_data: 'bosh data',
          instance_id: 'instance',
          agent_id: 'agent',
          director_name: 'Director',
          director_uuid: SecureRandom.uuid
        )

        snapshot_id = @cpi.snapshot_disk(disk_id, snapshot_metadata)
        expect(snapshot_id).not_to be_nil

        @cpi.delete_snapshot(snapshot_id)
        Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
          @cpi.detach_disk(instance_id, disk_id)
          true
        end
        @cpi.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end
    end
  end
end
