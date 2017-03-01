require 'spec_helper'
require 'securerandom'
require 'tempfile'
require 'logger'
require 'cloud'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @subscription_id                 = ENV['BOSH_AZURE_SUBSCRIPTION_ID']                 || raise("Missing BOSH_AZURE_SUBSCRIPTION_ID")
    @tenant_id                       = ENV['BOSH_AZURE_TENANT_ID']                       || raise("Missing BOSH_AZURE_TENANT_ID")
    @client_id                       = ENV['BOSH_AZURE_CLIENT_ID']                       || raise("Missing BOSH_AZURE_CLIENT_ID")
    @client_secret                   = ENV['BOSH_AZURE_CLIENT_SECRET']                   || raise("Missing BOSH_AZURE_CLIENT_secret")
    @stemcell_id                     = ENV['BOSH_AZURE_STEMCELL_ID']                     || raise("Missing BOSH_AZURE_STEMCELL_ID")
    @ssh_public_key                  = ENV['BOSH_AZURE_SSH_PUBLIC_KEY']                  || raise("Missing BOSH_AZURE_SSH_PUBLIC_KEY")
    @default_security_group          = ENV['BOSH_AZURE_DEFAULT_SECURITY_GROUP']          || raise("Missing BOSH_AZURE_DEFAULT_SECURITY_GROUP")
    @resource_group_name_for_vms     = ENV['BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_VMS']     || raise("Missing BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_VMS")
    @resource_group_name_for_network = ENV['BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_NETWORK'] || raise("Missing BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_NETWORK")
    @primary_public_ip               = ENV['BOSH_AZURE_PRIMARY_PUBLIC_IP']               || raise("Missing BOSH_AZURE_PRIMARY_PUBLIC_IP")
    @secondary_public_ip             = ENV['BOSH_AZURE_SECONDARY_PUBLIC_IP']             || raise("Missing BOSH_AZURE_SECONDARY_PUBLIC_IP")
  end

  let(:azure_environment)    { ENV.fetch('BOSH_AZURE_ENVIRONMENT', 'AzureCloud') }
  let(:storage_account_name) { ENV.fetch('BOSH_AZURE_STORAGE_ACCOUNT_NAME', nil) }
  let(:use_managed_disks)    { ENV.fetch('BOSH_AZURE_USE_MANAGED_DISKS', false).to_s == 'true' }
  let(:vnet_name)            { ENV.fetch('BOSH_AZURE_VNET_NAME', 'boshvnet-crp') }
  let(:subnet_name)          { ENV.fetch('BOSH_AZURE_SUBNET_NAME', 'BOSH1') }
  let(:second_subnet_name)   { ENV.fetch('BOSH_AZURE_SECOND_SUBNET_NAME', 'BOSH2') }
  let(:instance_type)        { ENV.fetch('BOSH_AZURE_INSTANCE_TYPE', 'Standard_D1_v2') }
  let(:vm_metadata)          { { deployment: 'deployment', job: 'cpi_spec', index: '0', delete_me: 'please' } }
  let(:network_spec)         { {} }
  let(:resource_pool)        { { 'instance_type' => instance_type } }

  let(:cloud_options) {
    {
      'azure' => {
        'environment' => azure_environment,
        'subscription_id' => @subscription_id,
        'resource_group_name' => @resource_group_name_for_vms,
        'tenant_id' => @tenant_id,
        'client_id' => @client_id,
        'client_secret' => @client_secret,
        'ssh_user' => 'vcap',
        'ssh_public_key' => @ssh_public_key,
        'default_security_group' => @default_security_group,
        'parallel_upload_thread_num' => 16,
      },
      'registry' => {
        'endpoint' => 'fake',
        'user' => 'fake',
        'password' => 'fake'
      }
    }
  }

  subject(:cpi) do
    cloud_options['azure']['storage_account_name'] = storage_account_name unless storage_account_name.nil?
    cloud_options['azure']['use_managed_disks'] = use_managed_disks
    described_class.new(cloud_options)
  end

  before {
    Bosh::Clouds::Config.configure(double('delegate', task_checkpoint: nil))
  }

  before { allow(Bosh::Clouds::Config).to receive_messages(logger: logger) }
  let(:logger) { Logger.new(STDERR) }

  before { allow(Bosh::Cpi::RegistryClient).to receive_messages(new: double('registry').as_null_object) }

  before { @disk_id_pool = Array.new }
  after {
    @disk_id_pool.each do |disk_id|
      logger.info("Cleanup: Deleting the disk `#{disk_id}'")
      cpi.delete_disk(disk_id) if disk_id
    end
  }

  context 'manual networking' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'manual',
          'ip' => "10.0.0.#{Random.rand(10..99)}",
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    }

    context 'without existing disks' do
      it 'should exercise the vm lifecycle' do
        vm_lifecycle do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)

          cpi.attach_disk(instance_id, disk_id)

          snapshot_metadata = vm_metadata.merge(
            bosh_data: 'bosh data',
            instance_id: 'instance',
            agent_id: 'agent',
            director_name: 'Director',
            director_uuid: SecureRandom.uuid
          )

          snapshot_id = cpi.snapshot_disk(disk_id, snapshot_metadata)
          expect(snapshot_id).not_to be_nil

          cpi.delete_snapshot(snapshot_id)
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: lambda { |n, _| [2**(n-1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end
          cpi.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        end
      end
    end

    context 'with existing disks' do
      let!(:existing_disk_id) { cpi.create_disk(2048, {}) }
      after { cpi.delete_disk(existing_disk_id) if existing_disk_id }

      it 'can excercise the vm lifecycle and list the disks' do
        vm_lifecycle do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil
          @disk_id_pool.push(disk_id)

          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)

          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: lambda { |n, _| [2**(n-1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end
          cpi.delete_disk(disk_id)
          @disk_id_pool.delete(disk_id)
        end
      end
    end

    context 'when vm with an attached disk is removed' do
      it 'should attach disk to a new vm' do
        disk_id = cpi.create_disk(2048, {})
        expect(disk_id).not_to be_nil
        @disk_id_pool.push(disk_id)

        vm_lifecycle do |instance_id|
          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)
        end

        begin
          new_instance_id = cpi.create_vm(
            SecureRandom.uuid,
            @stemcell_id,
            resource_pool,
            network_spec
          )

          expect {
            cpi.attach_disk(new_instance_id, disk_id)
          }.to_not raise_error

          expect(cpi.get_disks(new_instance_id)).to include(disk_id)
        ensure
          cpi.delete_vm(new_instance_id) if new_instance_id
        end
      end
    end
  end

  context 'dynamic networking' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'vip networking' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        },
        'network_b' => {
          'type' => 'vip',
          'ip' => @primary_public_ip
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'multiple nics' do
    let(:instance_type) { 'Standard_D2' }
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'default' => ['dns', 'gateway'],
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        },
        'network_b' => {
          'type' => 'manual',
          'ip' => "10.0.1.#{Random.rand(10..99)}",
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => second_subnet_name
          }
        },
        'network_c' => {
          'type' => 'vip',
          'ip' => @primary_public_ip
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'Creating multiple VMs in availability sets' do
    let(:resource_pool) {
      {
        'instance_type' => instance_type,
        'availability_set' => SecureRandom.uuid,
        'ephemeral_disk' => {
          'size' => 20480
        }
      }
    }

    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle(2) do |instance_id|
        disk_id = cpi.create_disk(2048, {}, instance_id)
        expect(disk_id).not_to be_nil
        @disk_id_pool.push(disk_id)

        cpi.attach_disk(instance_id, disk_id)

        snapshot_metadata = vm_metadata.merge(
          bosh_data: 'bosh data',
          instance_id: 'instance',
          agent_id: 'agent',
          director_name: 'Director',
          director_uuid: SecureRandom.uuid
        )

        snapshot_id = cpi.snapshot_disk(disk_id, snapshot_metadata)
        expect(snapshot_id).not_to be_nil

        cpi.delete_snapshot(snapshot_id)
        Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: lambda { |n, _| [2**(n-1), 30].min }) do
          cpi.detach_disk(instance_id, disk_id)
          true
        end
        cpi.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end
    end
  end

  context 'When the resource group name is specified for the vnet & security groups' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'resource_group_name' => @resource_group_name_for_network,
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'When the resource group name is specified for the public IP' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        },
        'network_b' => {
          'type' => 'vip',
          'ip' => @secondary_public_ip,
          'cloud_properties' => {
            'resource_group_name' => @resource_group_name_for_network
          }
        }
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'when assigning dynamic public IP to VM' do
    let(:network_spec) {
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    }
    let(:resource_pool) {
      {
        'instance_type' => instance_type,
        'assign_dynamic_public_ip' => true,
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  def vm_lifecycle(nums = 1)
    instance_id_pool = Array.new
    for i in 1..nums
      logger.info("Creating VM with stemcell_id=`#{@stemcell_id}'")
      instance_id = cpi.create_vm(
        SecureRandom.uuid,
        @stemcell_id,
        resource_pool,
        network_spec)
      expect(instance_id).to be

      logger.info("Checking VM existence instance_id=`#{instance_id}'")
      expect(cpi.has_vm?(instance_id)).to be(true)
      instance_id_pool.push(instance_id)

      logger.info("Setting VM metadata instance_id=`#{instance_id}'")
      cpi.set_vm_metadata(instance_id, vm_metadata)

      cpi.reboot_vm(instance_id)

      yield(instance_id) if block_given?
    end
  ensure
    instance_id_pool.each do |instance_id|
      cpi.delete_vm(instance_id) unless instance_id.nil?
    end
  end

end
