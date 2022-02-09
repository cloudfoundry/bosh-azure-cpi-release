# frozen_string_literal: true

require 'spec_helper'
require 'cloud'
require 'open3'
require 'securerandom'
require 'tempfile'
require 'rspec/retry'

RSpec.configure do |rspec_config|
  rspec_config.verbose_retry = true
  rspec_config.display_try_failure_messages = true

  rspec_config.before(:all) do
    # CPI global configurations
    @azure_environment           = ENV.fetch('BOSH_AZURE_ENVIRONMENT')
    @subscription_id             = ENV.fetch('BOSH_AZURE_SUBSCRIPTION_ID')
    @tenant_id                   = ENV.fetch('BOSH_AZURE_TENANT_ID')
    @client_id                   = ENV.fetch('BOSH_AZURE_CLIENT_ID')
    @client_secret               = ENV.fetch('BOSH_AZURE_CLIENT_SECRET')
    @location                    = ENV.fetch('BOSH_AZURE_LOCATION')
    @ssh_public_key              = ENV.fetch('BOSH_AZURE_SSH_PUBLIC_KEY')
    @default_resource_group_name = ENV.fetch('BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME')
    @storage_account_name        = ENV.fetch('BOSH_AZURE_STORAGE_ACCOUNT_NAME')
    @use_managed_disks           = ENV.fetch('BOSH_AZURE_USE_MANAGED_DISKS', false).to_s == 'true'

    @stemcell_id                 = ENV.fetch('BOSH_AZURE_STEMCELL_ID')

    @instance_type               = ENV.fetch('BOSH_AZURE_INSTANCE_TYPE', 'Standard_D1_v2')

    @vnet_name                   = ENV.fetch('BOSH_AZURE_VNET_NAME')
    @subnet_name                 = ENV.fetch('BOSH_AZURE_SUBNET_NAME')
  end

  rspec_config.before do
    @registry = instance_double(Bosh::Cpi::RegistryClient).as_null_object
    allow(Bosh::Cpi::RegistryClient).to receive(:new).and_return(@registry)
    allow(@registry).to receive(:read_settings).and_return({})

    @logger = Bosh::AzureCloud::CPILogger.get_logger(STDERR)
    allow(Bosh::Clouds::Config).to receive_messages(logger: @logger)

    azure_config_hash = {
      'environment' => @azure_environment,
      'location' => @location,
      'subscription_id' => @subscription_id,
      'tenant_id' => @tenant_id,
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'ssh_user' => 'vcap',
      'ssh_public_key' => @ssh_public_key,
      'resource_group_name' => @default_resource_group_name,
      'use_managed_disks' => @use_managed_disks,
      'storage_account_name' => @storage_account_name,
      'parallel_upload_thread_num' => 16
    }
    @azure_config = Bosh::AzureCloud::AzureConfig.new(azure_config_hash)

    @cloud_options = {
      'azure' => azure_config_hash,
      'registry' => {
        'endpoint' => 'fake',
        'user' => 'fake',
        'password' => 'fake'
      }
    }
    @cpi = Bosh::AzureCloud::Cloud.new(@cloud_options, 1)
    @cpi2 = Bosh::AzureCloud::Cloud.new(@cloud_options, 2)

    @vm_metadata = { deployment: 'deployment', job: 'cpi_spec', index: '0', delete_me: 'please' }
  end
end

def get_azure_client
  @azure_client ||= Bosh::AzureCloud::AzureClient.new(@cpi.config.azure, @logger)
end

def vm_lifecycle(stemcell_id: @stemcell_id, cpi: @cpi)
  result = cpi.create_vm(
    SecureRandom.uuid,
    stemcell_id,
    vm_properties,
    network_spec
  )

  if cpi.api_version == Bosh::AzureCloud::Cloud::CURRENT_API_VERSION
    expect(result).to be_a(Array)
    instance_id = result[0]
    networks = result[1]
    expect(networks).to be_a(Hash)
  else
    expect(result).to be_a(String)
    instance_id = result
  end

  expect(instance_id).not_to be_nil

  expect(cpi.has_vm?(instance_id)).to be(true)

  cpi.set_vm_metadata(instance_id, @vm_metadata)

  cpi.reboot_vm(instance_id)

  yield(instance_id) if block_given?
ensure
  cpi.delete_vm(instance_id) if instance_id
end

def run_command(command)
  output, status = Open3.capture2e(command)
  raise "'#{command}' failed with exit status=#{status.exitstatus} [#{output}]" if status.exitstatus != 0
end
