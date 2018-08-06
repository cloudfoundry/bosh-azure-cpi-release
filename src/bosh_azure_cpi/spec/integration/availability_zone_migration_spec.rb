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
  let(:availability_zone)    { Random.rand(1..3).to_s }
  let(:vm_properties)        do
    {
      'instance_type' => instance_type,
      'resource_group_name' => @additional_resource_group_name,
      'assign_dynamic_public_ip' => true,
      'availability_zone' => availability_zone
    }
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

  subject(:cpi_unmanaged) do
    cloud_options['azure']['use_managed_disks'] = false
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

  context 'Migrate regional VM to zonal VM', availability_zone: true do
    context 'when the regional VM is with unmanaged disks' do
      it 'should exercise the vm lifecycle' do
        begin
          # Create an unmanaged disk
          disk_id = cpi_unmanaged.create_disk(2048, {}, nil)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)

          # Create a zonal VM
          logger.info("Creating managed zonal VM with stemcell_id='#{@stemcell_id}'")
          instance_id = cpi.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)

          logger.info("Checking managed VM existence instance_id='#{instance_id}'")
          expect(cpi.has_vm?(instance_id)).to be(true)

          # Migrate the unmanaged regional disk to a managed zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
          cpi.attach_disk(instance_id, disk_id)

          # Detach the zonal disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end

          # Delete the zonal disk, and the migrated unmanaged regional disk
          cpi.delete_disk(disk_id)
          cpi_unmanaged.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        ensure
          cpi.delete_vm(instance_id) unless instance_id.nil?
        end
      end
    end

    context 'when the regional VM is with managed disks' do
      it 'should exercise the vm lifecycle' do
        begin
          # Create an regional disk
          disk_id = cpi.create_disk(2048, {}, nil)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)

          # Create a zonal VM
          logger.info("Creating managed zonal VM with stemcell_id='#{@stemcell_id}'")
          instance_id = cpi.create_vm(SecureRandom.uuid, @stemcell_id, vm_properties, network_spec)

          logger.info("Checking zonal VM existence instance_id='#{instance_id}'")
          expect(cpi.has_vm?(instance_id)).to be(true)

          # Migrate the regional disk to a zonal disk, and attach the zonal disk to the zonal VM. The disk_id won't be changed.
          cpi.attach_disk(instance_id, disk_id)

          # Detach the zonal disk
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end

          # Delete the zonal disk
          cpi.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        ensure
          cpi.delete_vm(instance_id) unless instance_id.nil?
        end
      end
    end
  end
end
