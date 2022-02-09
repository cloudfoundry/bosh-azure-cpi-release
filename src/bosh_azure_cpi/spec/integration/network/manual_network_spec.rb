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

  let(:vm_properties) do
    {
      'instance_type' => @instance_type
    }
  end

  context 'manual networking' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'manual',
          'ip' => "10.0.0.#{Random.rand(10..99)}",
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        }
      }
    end

    context 'without existing disks' do
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

    context 'with existing disks' do
      let!(:existing_disk_id) { @cpi.create_disk(2048, {}) }

      after { @cpi.delete_disk(existing_disk_id) if existing_disk_id }

      it 'can excercise the vm lifecycle and list the disks' do
        vm_lifecycle do |instance_id|
          disk_id = @cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)

          @cpi.attach_disk(instance_id, disk_id)
          expect(@cpi.get_disks(instance_id)).to include(disk_id)

          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            @cpi.detach_disk(instance_id, disk_id)
            true
          end
          @cpi.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        end
      end
    end

    context 'when vm with an attached disk is removed' do
      it 'should attach disk to a new vm' do
        disk_id = @cpi.create_disk(2048, {})
        expect(disk_id).not_to be_nil
        @disk_id_pool.push(disk_id)

        vm_lifecycle do |instance_id|
          @cpi.attach_disk(instance_id, disk_id)
          expect(@cpi.get_disks(instance_id)).to include(disk_id)
        end

        begin
          new_instance_id = @cpi.create_vm(
            SecureRandom.uuid,
            @stemcell_id,
            vm_properties,
            network_spec
          )

          expect do
            @cpi.attach_disk(new_instance_id, disk_id)
          end.not_to raise_error

          expect(@cpi.get_disks(new_instance_id)).to include(disk_id)
        ensure
          @cpi.delete_vm(new_instance_id) if new_instance_id
        end
      end
    end
  end
end
