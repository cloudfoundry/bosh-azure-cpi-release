require 'spec_helper'
require 'securerandom'
require 'tempfile'
require 'logger'
require 'cloud'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @subscription_id      = ENV['BOSH_AZURE_SUBSCRIPTION_ID']      || raise("Missing BOSH_AZURE_SUBSCRIPTION_ID")
    @storage_account_name = ENV['BOSH_AZURE_STORAGE_ACCOUNT_NAME'] || raise("Missing BOSH_AZURE_STORAGE_ACCOUNT_NAME")
    @resource_group_name  = ENV['BOSH_AZURE_RESOURCE_GROUP_NAME']  || raise("Missing BOSH_AZURE_RESOURCE_GROUP_NAME")
    @tenant_id            = ENV['BOSH_AZURE_TENANT_ID']            || raise("Missing BOSH_AZURE_TENANT_ID")
    @client_id            = ENV['BOSH_AZURE_CLIENT_ID']            || raise("Missing BOSH_AZURE_CLIENT_ID")
    @client_secret        = ENV['BOSH_AZURE_CLIENT_SECRET']        || raise("Missing BOSH_AZURE_CLIENT_secret")
    @certificate_file     = ENV['BOSH_AZURE_CERTIFICATE_FILE']     || raise("Missing BOSH_AZURE_CERTIFICATE_FILE")
    @stemcell_file        = ENV['BOSH_AZURE_STEMCELL_FILE']        || raise("Missing BOSH_AZURE_STEMCELL_FILE")
  end

  let(:manual_ip)       { ENV.fetch('BOSH_AZURE_LIFECYCLE_MANUAL_IP', '10.0.0.6') }
  let(:vnet_name)       { ENV.fetch('BOSH_AZURE_VNET_NAME', 'boshvnet-crp') }
  let(:subnet_name)     { ENV.fetch('BOSH_AZURE_SUBNET_NAME', 'Bosh') }

  let(:manual_networks) {
    {
      "bosh" => {
        "type"    => "manual",
        "ip"      => manual_ip,
        "cloud_properties" => {
          "virtual_network_name" => vnet_name,
          "subnet_name" => subnet_name
        }
      }
    }
  }

  let(:dynamic_networks) {
    {
      'default' => {
        'type' => 'dynamic',
        'cloud_properties' => {
          "virtual_network_name" => vnet_name,
          'subnet_name' => subnet_name
        }
      }
    }
  }

  let(:ssh_user)        { ENV.fetch('BOSH_AZURE_SSH_USER', 'vcap') }
  let(:ssh_certificate) {
    raise("#{@certificate_file} not exists") unless FileTest::exist?(@certificate_file)
    IO.read(@certificate_file)
  }

  subject(:cpi) do
    described_class.new(
      'azure' => {
        'environment' => 'AzureCloud',
        'subscription_id' => @subscription_id,
        'storage_account_name' => @storage_account_name,
        'resource_group_name' => @resource_group_name,
        'tenant_id' => @tenant_id,
        'client_id' => @client_id,
        'client_secret' => @client_secret,
        'ssh_user' => ssh_user,
        'ssh_certificate' => ssh_certificate,
        'parallel_upload_thread_num' => 16
      },
      'registry' => {
        'endpoint' => 'fake',
        'user' => 'fake',
        'password' => 'fake'
      }
    )
  end

  let(:instance_type)   { ENV.fetch('BOSH_AZURE_INSTANCE_TYPE', 'Standard_D1') }
  let(:resource_pool)   { { 'instance_type' => instance_type } }
  let(:vm_metadata)   { { deployment: 'deployment', job: 'cpi_spec', index: '0', delete_me: 'please' } }

  before {
    Azure.config.storage_blob_host = "https://#{@storage_account_name}.blob.core.windows.net"
    Bosh::Clouds::Config.configure(double('delegate', task_checkpoint: nil))
  }

  before { allow(Bosh::Clouds::Config).to receive_messages(logger: logger) }
  #let(:logger) { Logger.new(STDERR) }
  let(:logger) { Logger.new('lifecycle.log') }

  before { allow(Bosh::Registry::Client).to receive_messages(new: double('registry').as_null_object) }

  before { @instance_id = nil }
  after  { cpi.delete_vm(@instance_id) if @instance_id }

  before { @disk_id = nil }
  after  { cpi.delete_disk(@disk_id) if @disk_id }

  #before { @stemcell_id = create_stemcell() }
  #after  { cpi.delete_stemcell(@stemcell_id) if @stemcell_id }
  before { @stemcell_id = "bosh-stemcell-410cc7cb-ac4a-4bf2-ae81-58c9c7145da2" }

  context 'manual networking' do
    context 'without existing disks' do
      it 'should exercise the vm lifecycle' do
        vm_lifecycle(@stemcell_id, manual_networks) do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil

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
        end
      end
    end

    context 'with existing disks' do
      let!(:existing_disk_id) { cpi.create_disk(2048, {}) }
      after  { cpi.delete_disk(existing_disk_id) if existing_disk_id }

      it 'can excercise the vm lifecycle and list the disks' do
        vm_lifecycle(@stemcell_id, manual_networks) do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil

          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)

          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: lambda { |n, _| [2**(n-1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end
        end
      end
    end

    context 'when vm with a attached disk is removed' do
      it 'should attach disk to a new vm' do
        disk_id = cpi.create_disk(2048, {})
        expect(disk_id).not_to be_nil

        vm_lifecycle(@stemcell_id, manual_networks) do |instance_id|
          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)
        end

        begin
          new_instance_id = cpi.create_vm(
            SecureRandom.uuid,
            @stemcell_id,
            resource_pool,
            manual_networks
          )

          expect {
            cpi.attach_disk(new_instance_id, disk_id)
          }.to_not raise_error

          expect(cpi.get_disks(new_instance_id)).to include(disk_id)
        ensure
          cpi.delete_vm(new_instance_id) if new_instance_id
          cpi.delete_disk(disk_id) if disk_id
        end
      end
    end
  end

  context 'dynamic networking' do
    context 'without existing disks' do
      it 'should exercise the vm lifecycle' do
        vm_lifecycle(@stemcell_id, dynamic_networks) do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil

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
        end
      end
    end

    context 'with existing disks' do
      let!(:existing_disk_id) { cpi.create_disk(2048, {}) }
      after  { cpi.delete_disk(existing_disk_id) if existing_disk_id }

      it 'can excercise the vm lifecycle and list the disks' do
        vm_lifecycle(@stemcell_id, dynamic_networks) do |instance_id|
          disk_id = cpi.create_disk(2048, {}, instance_id)
          expect(disk_id).not_to be_nil

          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)

          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: lambda { |n, _| [2**(n-1), 30].min }) do
            cpi.detach_disk(instance_id, disk_id)
            true
          end
        end
      end
    end

    context 'when vm with a attached disk is removed' do
      it 'should attach disk to a new vm' do
        disk_id = cpi.create_disk(2048, {})
        expect(disk_id).not_to be_nil

        vm_lifecycle(@stemcell_id, dynamic_networks) do |instance_id|
          cpi.attach_disk(instance_id, disk_id)
          expect(cpi.get_disks(instance_id)).to include(disk_id)
        end

        begin
          new_instance_id = cpi.create_vm(
            SecureRandom.uuid,
            @stemcell_id,
            resource_pool,
            manual_networks
          )

          expect {
            cpi.attach_disk(new_instance_id, disk_id)
          }.to_not raise_error

          expect(cpi.get_disks(new_instance_id)).to include(disk_id)
        ensure
          cpi.delete_vm(new_instance_id) if new_instance_id
          cpi.delete_disk(disk_id) if disk_id
        end
      end
    end
  end

  context 'Creating multiple VMs in availability sets' do
    let(:resource_pool) {
      {
        'instance_type' => instance_type,
        'availability_set' => 'foo-availability-set'
      }
    }

    it 'should exercise the vm lifecycle' do
      vm_lifecycle(@stemcell_id, dynamic_networks, 2) do |instance_id|
        disk_id = cpi.create_disk(2048, {}, instance_id)
        expect(disk_id).not_to be_nil

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
      end
    end
  end

  def vm_lifecycle(stemcell_id, network_spec, nums=1)
    instance_id_pool = Array.new
    for i in 1..nums 
      logger.info("Creating VM with stemcell_id=#{stemcell_id}")
      instance_id = cpi.create_vm(
        SecureRandom.uuid,
        stemcell_id,
        resource_pool,
        network_spec)
      expect(instance_id).to be

      logger.info("Checking VM existence instance_id=#{instance_id}")
      expect(cpi.has_vm?(instance_id)).to be(true)
      instance_id_pool.push(instance_id)

      logger.info("Setting VM metadata instance_id=#{instance_id}")
      cpi.set_vm_metadata(instance_id, vm_metadata)

      cpi.reboot_vm(instance_id)
      
      yield(instance_id) if block_given?
    end
  ensure
    instance_id_pool.each do |instance_id|
      cpi.delete_vm(instance_id) unless instance_id.nil?
    end
  end

  def create_stemcell
    path = extract_image(@stemcell_file)
    stemcell_id = cpi.create_stemcell(path, {})
  end

  def extract_image(image_path)
    puts ("Unpacking image: #{image_path}")
    run_command("tar -xf #{image_path} -C /mnt/")
    "/mnt/image"
  end
  
  def run_command(command)
    output, status = Open3.capture2e(command)
    if status.exitstatus != 0
      puts "'#{command}' failed with exit status=#{status.exitstatus} [#{output}]"
    end
  end
end
