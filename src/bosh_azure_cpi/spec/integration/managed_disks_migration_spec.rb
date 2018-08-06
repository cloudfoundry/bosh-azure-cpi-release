# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'tempfile'
require 'logger'
require 'cloud'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @subscription_id                 = ENV['BOSH_AZURE_SUBSCRIPTION_ID']                 || raise('Missing BOSH_AZURE_SUBSCRIPTION_ID')
    @tenant_id                       = ENV['BOSH_AZURE_TENANT_ID']                       || raise('Missing BOSH_AZURE_TENANT_ID')
    @client_id                       = ENV['BOSH_AZURE_CLIENT_ID']                       || raise('Missing BOSH_AZURE_CLIENT_ID')
    @client_secret                   = ENV['BOSH_AZURE_CLIENT_SECRET']                   || raise('Missing BOSH_AZURE_CLIENT_secret')
    @stemcell_id                     = ENV['BOSH_AZURE_STEMCELL_ID']                     || raise('Missing BOSH_AZURE_STEMCELL_ID')
    @ssh_public_key                  = ENV['BOSH_AZURE_SSH_PUBLIC_KEY']                  || raise('Missing BOSH_AZURE_SSH_PUBLIC_KEY')
    @default_security_group          = ENV['BOSH_AZURE_DEFAULT_SECURITY_GROUP']          || raise('Missing BOSH_AZURE_DEFAULT_SECURITY_GROUP')
    @default_resource_group_name     = ENV['BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME']     || raise('Missing BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME')
    @additional_resource_group_name  = ENV['BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME']  || raise('Missing BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME')
  end

  let(:azure_environment)    { ENV.fetch('BOSH_AZURE_ENVIRONMENT', 'AzureCloud') }
  let(:storage_account_name) { ENV.fetch('BOSH_AZURE_STORAGE_ACCOUNT_NAME', nil) }
  let(:vnet_name)            { ENV.fetch('BOSH_AZURE_VNET_NAME', 'boshvnet-crp') }
  let(:subnet_name)          { ENV.fetch('BOSH_AZURE_SUBNET_NAME', 'BOSH1') }
  let(:instance_type)        { ENV.fetch('BOSH_AZURE_INSTANCE_TYPE', 'Standard_D1_v2') }
  let(:vm_metadata)          { { deployment: 'deployment', job: 'cpi_spec', index: '0', delete_me: 'please' } }
  let(:network_spec)         { {} }
  let(:vm_properties)        do
    {
      'instance_type' => instance_type,
      'resource_group_name' => @additional_resource_group_name
    }
  end
  let(:snapshot_metadata) do
    vm_metadata.merge(
      bosh_data: 'bosh data',
      instance_id: 'instance',
      agent_id: 'agent',
      director_name: 'Director',
      director_uuid: SecureRandom.uuid
    )
  end

  let(:cloud_options) do
    {
      'azure' => {
        'environment' => azure_environment,
        'subscription_id' => @subscription_id,
        'resource_group_name' => @default_resource_group_name,
        'storage_account_name' => storage_account_name,
        'tenant_id' => @tenant_id,
        'client_id' => @client_id,
        'client_secret' => @client_secret,
        'ssh_user' => 'vcap',
        'ssh_public_key' => @ssh_public_key,
        'default_security_group' => @default_security_group,
        'parallel_upload_thread_num' => 16
      },
      'registry' => {
        'endpoint' => 'fake',
        'user' => 'fake',
        'password' => 'fake'
      }
    }
  end

  subject(:cpi) do
    cloud_options['azure']['use_managed_disks'] = true
    described_class.new(cloud_options)
  end

  before do
    Bosh::Clouds::Config.configure(double('delegate', task_checkpoint: nil))
  end

  before { allow(Bosh::Clouds::Config).to receive_messages(logger: logger) }
  let(:logger) { Logger.new(STDERR) }

  before { allow(Bosh::Cpi::RegistryClient).to receive_messages(new: double('registry').as_null_object) }

  before { @disk_id_pool = [] }
  after do
    @disk_id_pool.each do |disk_id|
      logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      cpi.delete_disk(disk_id) if disk_id
    end
  end

  context 'Migrate from unmanaged disks deployment to managed disks deployment' do
    subject(:cpi_unmanaged) do
      cloud_options['azure']['use_managed_disks'] = false
      described_class.new(cloud_options)
    end

    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    end

    context 'Without availability set' do
      it 'should exercise the vm lifecycle' do
        begin
          # Create an unmanaged VM
          logger.info("Creating unmanaged VM with stemcell_id='#{@stemcell_id}'")
          unmanaged_instance_id = cpi_unmanaged.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)
          logger.info("Checking unmanaged VM existence instance_id='#{unmanaged_instance_id}'")
          expect(cpi_unmanaged.has_vm?(unmanaged_instance_id)).to be(true)
          logger.info("Setting VM metadata instance_id='#{unmanaged_instance_id}'")
          cpi_unmanaged.set_vm_metadata(unmanaged_instance_id, vm_metadata)
          cpi_unmanaged.reboot_vm(unmanaged_instance_id)

          # Create an unmanaged disk, and attach it to the unmanaged VM
          disk_id = cpi_unmanaged.create_disk(2048, {}, unmanaged_instance_id)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)
          cpi_unmanaged.attach_disk(unmanaged_instance_id, disk_id)

          # Create and delete an unmanaged snapshot
          unmanaged_snapshot_id = cpi_unmanaged.snapshot_disk(disk_id, snapshot_metadata)
          expect(unmanaged_snapshot_id).not_to be_nil
          cpi_unmanaged.delete_snapshot(unmanaged_snapshot_id)

          logger.info('Assume that the new BOSH director (use_managed_disks=true) is deployed.') # After this line, cpi instead of cpi_unmanaged will be used

          # Even use_managed_disks is enabled, but the unmanaged VM and disks have not been updated. It should succeed to snapshot the unmanaged disk.
          unmanaged_snapshot_id = cpi.snapshot_disk(disk_id, snapshot_metadata)
          expect(unmanaged_snapshot_id).not_to be_nil
          cpi.delete_snapshot(unmanaged_snapshot_id)

          logger.info('The new BOSH director starts to update the unmanaged VM to a managed VM')

          # Detach the unmanaged disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            cpi.detach_disk(unmanaged_instance_id, disk_id)
            true
          end

          # Delete the unmanaged VM
          cpi.delete_vm(unmanaged_instance_id)

          # Create a managed VM
          logger.info("Creating managed VM with stemcell_id='#{@stemcell_id}'")
          managed_instance_id = cpi.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)
          logger.info("Checking managed VM existence instance_id='#{managed_instance_id}'")
          expect(cpi.has_vm?(managed_instance_id)).to be(true)

          # Migrate the unmanaged disk to a managed disk, and attach the managed disk to the managed VM. The disk_id won't be changed.
          cpi.attach_disk(managed_instance_id, disk_id)

          # Create and delete a managed snapshot
          managed_snapshot_id = cpi.snapshot_disk(disk_id, snapshot_metadata)
          expect(managed_snapshot_id).not_to be_nil
          cpi.delete_snapshot(managed_snapshot_id)

          # Detach the managed disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            cpi.detach_disk(managed_instance_id, disk_id)
            true
          end

          # Delete the managed disk, and the migrated unmanaged disk
          cpi.delete_disk(disk_id)
          cpi_unmanaged.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        ensure
          cpi_unmanaged.delete_vm(unmanaged_instance_id) unless unmanaged_instance_id.nil?
          cpi.delete_vm(managed_instance_id) unless managed_instance_id.nil?
        end
      end
    end

    context 'With availability set' do
      let(:vm_properties) do
        {
          'instance_type' => instance_type,
          'availability_set' => SecureRandom.uuid,
          'platform_fault_domain_count' => 2,
          'ephemeral_disk' => {
            'size' => 20_480
          }
        }
      end

      it 'should exercise the vm lifecycle' do
        vm_count = 3
        unmanaged_instance_id_pool = []
        managed_instance_id_pool = []
        instance_id_and_disk_id_pool = []
        begin
          unmanaged_vm_lifecycles = []
          vm_count.times do |i|
            unmanaged_vm_lifecycles[i] = Thread.new do
              # Create an unmanaged VM
              logger.info("Creating VM with stemcell_id='#{@stemcell_id}'")
              instance_id = cpi_unmanaged.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)
              expect(instance_id).to be
              unmanaged_instance_id_pool.push(instance_id)
              logger.info("Checking VM existence instance_id='#{instance_id}'")
              expect(cpi_unmanaged.has_vm?(instance_id)).to be(true)
              logger.info("Setting VM metadata instance_id='#{instance_id}'")
              cpi_unmanaged.set_vm_metadata(instance_id, vm_metadata)
              cpi_unmanaged.reboot_vm(instance_id)

              # Create an unmanaged disk, and attach it to the unmanaged VM
              disk_id = cpi_unmanaged.create_disk(2048, {}, instance_id)
              expect(disk_id).not_to be_nil
              @disk_id_pool.push(disk_id)
              cpi_unmanaged.attach_disk(instance_id, disk_id)

              instance_id_and_disk_id_pool.push(
                instance_id: instance_id,
                disk_id: disk_id
              )
            end
          end
          unmanaged_vm_lifecycles.each(&:join)

          logger.info('Assume that the new BOSH director (use_managed_disks=true) is deployed.') # After this line, cpi instead of cpi_unmanaged will be used
          logger.info('The new BOSH director starts to update the unmanaged VM to an managed VM one by one')

          managed_vm_lifecycles = []
          vm_count.times do |i|
            managed_vm_lifecycles[i] = Thread.new do
              instance_id_and_disk_id = instance_id_and_disk_id_pool[i]
              unmanaged_instance_id = instance_id_and_disk_id[:instance_id]
              disk_id = instance_id_and_disk_id[:disk_id]

              # Delete the unmanaged VM
              cpi_unmanaged.delete_vm(unmanaged_instance_id) unless unmanaged_instance_id.nil?

              # Create a managed VM
              logger.info("Creating managed VM with stemcell_id='#{@stemcell_id}'")
              managed_instance_id = cpi.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)
              logger.info("Checking managed VM existence instance_id='#{managed_instance_id}'")
              expect(cpi.has_vm?(managed_instance_id)).to be(true)
              managed_instance_id_pool.push(managed_instance_id)

              # Migrate the unmanaged disk to a managed disk, and attach the managed disk to the VM. The disk_id won't be changed.
              cpi.attach_disk(managed_instance_id, disk_id)

              # Create and delete a managed snapshot
              managed_snapshot_id = cpi.snapshot_disk(disk_id, snapshot_metadata)
              expect(managed_snapshot_id).not_to be_nil
              cpi.delete_snapshot(managed_snapshot_id)

              # Detach the managed disk
              Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
                cpi.detach_disk(managed_instance_id, disk_id)
                true
              end

              # Delete the managed disk, and the migrated unmanaged disk
              cpi.delete_disk(disk_id)
              cpi_unmanaged.delete_disk(disk_id)
              @disk_id_pool.delete(disk_id)
            end
          end
          managed_vm_lifecycles.each(&:join)
        ensure
          unmanaged_instance_id_pool.each do |unmanaged_instance_id|
            cpi_unmanaged.delete_vm(unmanaged_instance_id) unless unmanaged_instance_id.nil?
          end
          managed_instance_id_pool.each do |managed_instance_id|
            cpi.delete_vm(managed_instance_id) unless managed_instance_id.nil?
          end
        end
      end
    end
  end
end
