# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @additional_resource_group_name = ENV.fetch('BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME')
    @secondary_public_ip            = ENV.fetch('BOSH_AZURE_SECONDARY_PUBLIC_IP')
  end

  before { @disk_id_pool = [] }
  after do
    @disk_id_pool.each do |disk_id|
      Bosh::AzureCloud::CPILogger.instance.logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      @cpi.delete_disk(disk_id) if disk_id
    end
  end

  let(:vm_properties) do
    {
      'instance_type' => @instance_type
    }
  end

  context 'When the resource group name is specified for the vnet & security groups' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'resource_group_name' => @additional_resource_group_name,
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        }
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'When the resource group name is specified for the public IP' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        },
        'network_b' => {
          'type' => 'vip',
          'ip' => @secondary_public_ip,
          'cloud_properties' => {
            'resource_group_name' => @additional_resource_group_name
          }
        }
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'When the resource group name is specified for the vm' do
    let(:vm_properties) do
      {
        'instance_type' => @instance_type,
        'resource_group_name' => @additional_resource_group_name,
        'availability_set' => SecureRandom.uuid,
        'ephemeral_disk' => {
          'size' => 20_480
        }
      }
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

    it 'should exercise the vm lifecycle' do
      vm_lifecycle do |instance_id|
        disk_id = @cpi.create_disk(2048, {}, instance_id)
        expect(disk_id).not_to be_nil
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
