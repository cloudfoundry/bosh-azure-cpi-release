# frozen_string_literal: true

require 'cloud'
require 'logger'
require 'spec_helper'
require 'securerandom'
require 'tempfile'
require 'yaml'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @subscription_id                 = ENV['BOSH_AZURE_SUBSCRIPTION_ID']                 || raise('Missing BOSH_AZURE_SUBSCRIPTION_ID')
    @tenant_id                       = ENV['BOSH_AZURE_TENANT_ID']                       || raise('Missing BOSH_AZURE_TENANT_ID')
    @client_id                       = ENV['BOSH_AZURE_CLIENT_ID']                       || raise('Missing BOSH_AZURE_CLIENT_ID')
    @client_secret                   = ENV['BOSH_AZURE_CLIENT_SECRET']                   || raise('Missing BOSH_AZURE_CLIENT_SECRET')
    @stemcell_id                     = ENV['BOSH_AZURE_STEMCELL_ID']                     || raise('Missing BOSH_AZURE_STEMCELL_ID')
    @ssh_public_key                  = ENV['BOSH_AZURE_SSH_PUBLIC_KEY']                  || raise('Missing BOSH_AZURE_SSH_PUBLIC_KEY')
    @default_security_group          = ENV['BOSH_AZURE_DEFAULT_SECURITY_GROUP']          || raise('Missing BOSH_AZURE_DEFAULT_SECURITY_GROUP')
    @default_resource_group_name     = ENV['BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME']     || raise('Missing BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME')
    @additional_resource_group_name  = ENV['BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME']  || raise('Missing BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME')
    @primary_public_ip               = ENV['BOSH_AZURE_PRIMARY_PUBLIC_IP']               || raise('Missing BOSH_AZURE_PRIMARY_PUBLIC_IP')
    @secondary_public_ip             = ENV['BOSH_AZURE_SECONDARY_PUBLIC_IP']             || raise('Missing BOSH_AZURE_SECONDARY_PUBLIC_IP')
    @application_gateway_name        = ENV['BOSH_AZURE_APPLICATION_GATEWAY_NAME']        || raise('Missing BOSH_AZURE_APPLICATION_GATEWAY_NAME')
    @application_security_group      = ENV['BOSH_AZURE_APPLICATION_SECURITY_GROUP']      || raise('Missing BOSH_AZURE_APPLICATION_SECURITY_GROUP')
    @stemcell_path                   = ENV['BOSH_AZURE_STEMCELL_PATH']                   || raise('Missing BOSH_AZURE_STEMCELL_PATH')
  end

  let(:azure_environment)          { ENV.fetch('BOSH_AZURE_ENVIRONMENT', 'AzureCloud') }
  let(:location)                   { ENV.fetch('BOSH_AZURE_LOCATION', 'westcentralus') }
  let(:storage_account_name)       { ENV.fetch('BOSH_AZURE_STORAGE_ACCOUNT_NAME', nil) }
  let(:extra_storage_account_name) { ENV.fetch('BOSH_AZURE_EXTRA_STORAGE_ACCOUNT_NAME', nil) }
  let(:use_managed_disks)          { ENV.fetch('BOSH_AZURE_USE_MANAGED_DISKS', false).to_s == 'true' }
  let(:vnet_name)                  { ENV.fetch('BOSH_AZURE_VNET_NAME', 'boshvnet-crp') }
  let(:subnet_name)                { ENV.fetch('BOSH_AZURE_SUBNET_NAME', 'BOSH1') }
  let(:second_subnet_name)         { ENV.fetch('BOSH_AZURE_SECOND_SUBNET_NAME', 'BOSH2') }
  let(:instance_type)              { ENV.fetch('BOSH_AZURE_INSTANCE_TYPE', 'Standard_D1_v2') }
  let(:vm_metadata)                { { deployment: 'deployment', job: 'cpi_spec', index: '0', delete_me: 'please' } }
  let(:network_spec)               { {} }
  let(:vm_properties)              { { 'instance_type' => instance_type } }

  let(:azure_config_hash) do
    {
      'environment' => azure_environment,
      'subscription_id' => @subscription_id,
      'resource_group_name' => @default_resource_group_name,
      'tenant_id' => @tenant_id,
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'ssh_user' => 'vcap',
      'ssh_public_key' => @ssh_public_key,
      'default_security_group' => @default_security_group,
      'parallel_upload_thread_num' => 16
    }
  end

  let(:azure_config) do
    Bosh::AzureCloud::AzureConfig.new(azure_config_hash)
  end

  let(:cloud_options) do
    {
      'azure' => azure_config_hash,
      'registry' => {
        'endpoint' => 'fake',
        'user' => 'fake',
        'password' => 'fake'
      }
    }
  end

  subject(:cpi) do
    cloud_options['azure']['storage_account_name'] = storage_account_name unless storage_account_name.nil?
    cloud_options['azure']['use_managed_disks'] = use_managed_disks
    described_class.new(cloud_options)
  end

  subject(:cpi_with_location) do
    cloud_options_with_location = cloud_options.dup
    cloud_options_with_location['azure']['storage_account_name'] = storage_account_name unless storage_account_name.nil?
    cloud_options_with_location['azure']['use_managed_disks'] = use_managed_disks
    cloud_options_with_location['azure']['location'] = location
    described_class.new(cloud_options_with_location)
  end

  subject(:cpi_without_default_nsg) do
    cloud_options_without_default_nsg = cloud_options.dup
    cloud_options_without_default_nsg['azure']['storage_account_name'] = storage_account_name unless storage_account_name.nil?
    cloud_options_without_default_nsg['azure']['use_managed_disks'] = use_managed_disks
    cloud_options_without_default_nsg['azure']['default_security_group'] = nil
    described_class.new(cloud_options_without_default_nsg)
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

  context '#stemcell' do
    context 'with heavy stemcell', heavy_stemcell: true do
      let(:extract_path)               { '/tmp/with-heavy-stemcell' }
      let(:image_path)                 { "#{extract_path}/image" }
      let(:image_metadata_path)        { "#{extract_path}/stemcell.MF" }

      before do
        FileUtils.mkdir_p(extract_path)
        run_command("tar -zxf #{@stemcell_path} -C #{extract_path}")
      end

      after do
        FileUtils.remove_dir(extract_path)
      end

      it 'should create/delete the stemcell' do
        heavy_stemcell_id = cpi.create_stemcell(image_path, {})
        expect(heavy_stemcell_id).not_to be_nil
        cpi.delete_stemcell(heavy_stemcell_id)
      end
    end

    context 'with light stemcell', light_stemcell: true do
      let(:extract_path)               { '/tmp/with-light-stemcell' }
      let(:image_path)                 { "#{extract_path}/image" }
      let(:image_metadata_path)        { "#{extract_path}/stemcell.MF" }

      before do
        FileUtils.mkdir_p(extract_path)
        run_command("tar -zxf #{@stemcell_path} -C #{extract_path}")
      end

      after do
        FileUtils.remove_dir(extract_path)
      end

      it 'should create/delete the stemcell' do
        stemcell_properties = YAML.load_file(image_metadata_path)['cloud_properties']

        light_stemcell_id = cpi.create_stemcell(image_path, stemcell_properties)
        expect(light_stemcell_id).not_to be_nil
        cpi.delete_stemcell(light_stemcell_id)
      end
    end
  end

  context '#calculate_vm_cloud_properties' do
    let(:vm_resources) do
      {
        'cpu' => 2,
        'ram' => 4096,
        'ephemeral_disk_size' => 32 * 1024
      }
    end
    it 'should return Azure specific cloud properties' do
      expect(cpi_with_location.calculate_vm_cloud_properties(vm_resources)).to eq(
        'instance_type' => 'Standard_F2',
        'ephemeral_disk' => {
          'size' => 32 * 1024
        }
      )
    end
  end

  context 'manual networking' do
    let(:network_spec) do
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
    end

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
          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
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

          Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
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
            vm_properties,
            network_spec
          )

          expect do
            cpi.attach_disk(new_instance_id, disk_id)
          end.to_not raise_error

          expect(cpi.get_disks(new_instance_id)).to include(disk_id)
        ensure
          cpi.delete_vm(new_instance_id) if new_instance_id
        end
      end
    end

    context 'when application_gateway is specified in resource pool' do
      let(:vm_properties) do
        {
          'instance_type' => instance_type,
          'application_gateway' => @application_gateway_name
        }
      end

      let(:threads) { 2 }
      let(:ip_address_start) do
        Random.rand(10..(100 - threads))
      end
      let(:ip_address_end) do
        ip_address_start + threads - 1
      end
      let(:ip_address_specs) do
        (ip_address_start..ip_address_end).to_a.collect { |x| "10.0.0.#{x}" }
      end
      let(:network_specs) do
        ip_address_specs.collect do |ip_address_spec|
          {
            'network_a' => {
              'type' => 'manual',
              'ip' => ip_address_spec,
              'cloud_properties' => {
                'virtual_network_name' => vnet_name,
                'subnet_name' => subnet_name
              }
            }
          }
        end
      end

      it 'should add the VM to the backend pool of application gateway' do
        ag_url = cpi.azure_client.rest_api_url(
          Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_NETWORK,
          Bosh::AzureCloud::AzureClient::REST_API_APPLICATION_GATEWAYS,
          name: @application_gateway_name
        )

        lifecycles = []
        threads.times do |i|
          lifecycles[i] = Thread.new do
            agent_id = SecureRandom.uuid
            ip_config_id = "/subscriptions/#{@subscription_id}/resourceGroups/#{@default_resource_group_name}/providers/Microsoft.Network/networkInterfaces/#{agent_id}-0/ipConfigurations/ipconfig0"
            begin
              new_instance_id = cpi.create_vm(
                agent_id,
                @stemcell_id,
                vm_properties,
                network_specs[i]
              )
              ag = cpi.azure_client.get_resource_by_id(ag_url)
              expect(ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations']).to include(
                'id' => ip_config_id
              )
            ensure
              cpi.delete_vm(new_instance_id) if new_instance_id
            end
            ag = cpi.azure_client.get_resource_by_id(ag_url)
            unless ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations'].nil?
              expect(ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations']).not_to include(
                'id' => ip_config_id
              )
            end
          end
        end
        lifecycles.each(&:join)
      end
    end
  end

  context 'dynamic networking' do
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

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'vip networking' do
    let(:network_spec) do
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
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'when default_security_group is not specified' do
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

    it 'should exercise the vm lifecycle' do
      begin
        logger.info("Creating VM with stemcell_id='#{@stemcell_id}'")
        instance_id = cpi_without_default_nsg.create_vm(
          SecureRandom.uuid,
          @stemcell_id,
          vm_properties,
          network_spec
        )
        expect(instance_id).to be

        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, azure_config.resource_group_name)
        network_interface = cpi_without_default_nsg.azure_client.get_network_interface_by_name(@default_resource_group_name, "#{instance_id_obj.vm_name}-0")
        nsg = network_interface[:network_security_group]
        expect(nsg).to be_nil
      ensure
        cpi_without_default_nsg.delete_vm(instance_id) unless instance_id.nil?
      end
    end
  end

  context 'multiple nics' do
    let(:instance_type) { 'Standard_D2_v2' }
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'default' => %w[dns gateway],
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
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'Creating multiple VMs in availability sets' do
    let(:vm_properties) do
      {
        'instance_type' => instance_type,
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
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    end

    it 'should exercise the vm lifecycle' do
      lifecycles = []
      2.times do |i|
        lifecycles[i] = Thread.new do
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
            Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
              cpi.detach_disk(instance_id, disk_id)
              true
            end
            cpi.delete_disk(disk_id)
            @disk_id_pool.delete(disk_id)
          end
        end
      end
      lifecycles.each(&:join)
    end
  end

  context 'When the resource group name is specified for the vnet & security groups' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'resource_group_name' => @additional_resource_group_name,
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
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
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
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
        'instance_type' => instance_type,
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
            'virtual_network_name' => vnet_name,
            'subnet_name' => subnet_name
          }
        }
      }
    end

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
        Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
          cpi.detach_disk(instance_id, disk_id)
          true
        end
        cpi.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end
    end
  end

  context 'when assigning dynamic public IP to VM' do
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
    let(:vm_properties) do
      {
        'instance_type' => instance_type,
        'assign_dynamic_public_ip' => true
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'when assigning a different storage account to VM', unmanaged_disks: true do
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
    let(:vm_properties) do
      {
        'instance_type' => instance_type,
        'storage_account_name' => extra_storage_account_name
      }
    end

    it 'should exercise the vm lifecycle' do
      lifecycles = []
      3.times do |i|
        lifecycles[i] = Thread.new do
          vm_lifecycle
        end
      end
      lifecycles.each(&:join)
    end
  end

  context 'when assigning application security groups to VM NIC', application_security_group: true do
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
    let(:vm_properties) do
      {
        'instance_type' => instance_type,
        'application_security_groups' => [@application_security_group]
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, azure_config.resource_group_name)
        network_interface = cpi.azure_client.get_network_interface_by_name(@default_resource_group_name, "#{instance_id_obj.vm_name}-0")
        asgs = network_interface[:application_security_groups]
        asg_names = []
        asgs.each do |asg|
          asg_names.push(asg[:name])
        end
        expect(asg_names).to eq([@application_security_group])
      end
    end
  end

  context 'when availability zone is specified', availability_zone: true do
    let(:availability_zone) { Random.rand(1..3).to_s }
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
    let(:vm_properties) do
      {
        'instance_type' => instance_type,
        'availability_zone' => availability_zone,
        'assign_dynamic_public_ip' => true
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, azure_config.resource_group_name)
        vm = cpi.azure_client.get_virtual_machine_by_name(@default_resource_group_name, instance_id_obj.vm_name)
        dynamic_public_ip = cpi.azure_client.get_public_ip_by_name(@default_resource_group_name, instance_id_obj.vm_name)
        expect(vm[:zone]).to eq(availability_zone)
        expect(dynamic_public_ip[:zone]).to eq(availability_zone)

        disk_id = cpi.create_disk(2048, {}, instance_id)
        expect(disk_id).not_to be_nil
        disk_id_obj = Bosh::AzureCloud::DiskId.parse(disk_id, azure_config.resource_group_name)
        disk = cpi.azure_client.get_managed_disk_by_name(@default_resource_group_name, disk_id_obj.disk_name)
        expect(disk[:zone]).to eq(availability_zone)
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
        Bosh::Common.retryable(tries: 20, on: Bosh::Clouds::DiskNotAttached, sleep: ->(n, _) { [2**(n - 1), 30].min }) do
          cpi.detach_disk(instance_id, disk_id)
          true
        end
        cpi.delete_disk(disk_id)
        @disk_id_pool.delete(disk_id)
      end
    end
  end

  def vm_lifecycle
    logger.info("Creating VM with stemcell_id='#{@stemcell_id}'")
    instance_id = cpi.create_vm(
      SecureRandom.uuid,
      @stemcell_id,
      vm_properties,
      network_spec
    )
    expect(instance_id).to be

    logger.info("Checking VM existence instance_id='#{instance_id}'")
    expect(cpi.has_vm?(instance_id)).to be(true)

    logger.info("Setting VM metadata instance_id='#{instance_id}'")
    cpi.set_vm_metadata(instance_id, vm_metadata)

    cpi.reboot_vm(instance_id)

    yield(instance_id) if block_given?
  ensure
    cpi.delete_vm(instance_id) unless instance_id.nil?
  end
end
