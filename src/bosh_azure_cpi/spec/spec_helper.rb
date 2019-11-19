# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'simplecov'
SimpleCov.start do
  add_filter '/spec'
end

require 'cloud/azure'
require 'fileutils'
require 'json'
require 'net/http'
require 'stringio'

MOCK_AZURE_SUBSCRIPTION_ID        = 'aa643f05-5b67-4d58-b433-54c2e9131a59'
MOCK_DEFAULT_STORAGE_ACCOUNT_NAME = '8853f441db154b438550a853'
MOCK_AZURE_STORAGE_ACCESS_KEY     = '3e795106-5887-4342-8c73-338facbb09fa'
MOCK_RESOURCE_GROUP_NAME          = '352ec9c1-6dd5-4a24-b11e-21bbe3d712ca'
MOCK_AZURE_TENANT_ID              = 'e441d583-68c5-46b3-bf43-ab49c5f07fed'
MOCK_AZURE_CLIENT_ID              = '62bd3eaa-e231-4e13-8baf-0e2cc8a898a1'
MOCK_AZURE_CLIENT_SECRET          = '0e67d8fc-150e-4cc0-bbf3-087e6c4b9e2a'
MOCK_SSH_PUBLIC_KEY               = 'bar'
MOCK_DEFAULT_SECURITY_GROUP       = 'fake-default-nsg-name'
MOCK_REQUEST_ID                   = '47504c59-37af-42f3-a386-22d0c2c73175'

# Let us keep the least API versions here for unit tests.
AZURE_API_VERSION                = '2015-06-15'
AZURE_STACK_API_VERSION          = '2015-06-15'
AZURE_CHINA_API_VERSION          = '2015-06-15'
AZURE_USGOV_API_VERSION          = '2015-06-15'
AZURE_GERMAN_API_VERSION         = '2015-06-15'
AZURE_RESOURCE_PROVIDER_COMPUTE  = '2018-04-01'
AZURE_RESOURCE_PROVIDER_GROUP    = '2016-06-01'
AZURE_RESOURCE_PROVIDER_NETWORK  = '2017-09-01'
AZURE_RESOURCE_PROVIDER_STORAGE  = '2017-10-01'

WINDOWS_VM_NAME_LENGTH          = 15
AZURE_MAX_RETRY_COUNT           = 10

ERROR_MSG_OPENSSL_RESET         = 'Connection reset by peer - SSL_connect'

STEMCELL_STORAGE_ACCOUNT_TAGS   = {
  'user-agent' => 'bosh',
  'type' => 'stemcell'
}.freeze

CPI_LOCK_DIR                            = '/tmp/azure_cpi'
CPI_LOCK_PREFIX                         = 'bosh-lock'
CPI_LOCK_PREFIX_STORAGE_ACCOUNT         = "#{CPI_LOCK_PREFIX}-storage-account"
CPI_LOCK_COPY_STEMCELL                  = "#{CPI_LOCK_PREFIX}-copy-stemcell"
CPI_LOCK_CREATE_USER_IMAGE              = "#{CPI_LOCK_PREFIX}-create-user-image"
CPI_LOCK_PREFIX_AVAILABILITY_SET        = "#{CPI_LOCK_PREFIX}-availability-set"
CPI_LOCK_EVENT_HANDLER                  = "#{CPI_LOCK_PREFIX}-event-handler"
STORAGE_ACCOUNT_NAME_CACHE              = '/tmp/azure_cpi_storage_account_name_cache'

def mock_cloud_options
  {
    'plugin' => 'azure',
    'properties' => {
      'azure' => {
        'environment' => 'AzureCloud',
        'subscription_id' => MOCK_AZURE_SUBSCRIPTION_ID,
        'storage_account_name' => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
        'resource_group_name' => MOCK_RESOURCE_GROUP_NAME,
        'tenant_id' => MOCK_AZURE_TENANT_ID,
        'client_id' => MOCK_AZURE_CLIENT_ID,
        'client_secret' => MOCK_AZURE_CLIENT_SECRET,
        'ssh_user' => 'vcap',
        'ssh_public_key' => MOCK_SSH_PUBLIC_KEY,
        'parallel_upload_thread_num' => 16,
        'default_security_group' => MOCK_DEFAULT_SECURITY_GROUP,
        'debug_mode' => false,
        'use_managed_disks' => false,
        'request_id' => MOCK_REQUEST_ID,
        'config_disk' => {
          'enabled' => false
        }
      },
      'registry' => {
        'endpoint' => 'localhost:42288',
        'user' => 'admin',
        'password' => 'admin'
      },
      'agent' => {
        'blobstore' => {
          'address' => '10.0.0.5'
        },
        'nats' => {
          'address' => '10.0.0.5'
        }
      }
    }
  }
end

def mock_azure_config(options = nil)
  if options.nil?
    Bosh::AzureCloud::AzureConfig.new(mock_cloud_options['properties']['azure'])
  else
    Bosh::AzureCloud::AzureConfig.new(options)
  end
end

def mock_azure_config_merge(override_options)
  Bosh::AzureCloud::AzureConfig.new(
    mock_cloud_options_merge(override_options, mock_cloud_options['properties']['azure'])
  )
end

def mock_cloud_properties_merge(override_options)
  mock_cloud_options_merge(override_options, mock_cloud_options['properties'])
end

def mock_cloud_options_merge(override_options, base_hash = mock_cloud_options)
  merged_options = {}
  override_options ||= {}

  override_options.each do |key, value|
    merged_options[key] = if !base_hash[key].nil? && value.is_a?(Hash)
                            mock_cloud_options_merge(override_options[key], base_hash[key])
                          else
                            value
                          end
  end
  extra_keys = base_hash.keys - override_options.keys
  extra_keys.each { |key| merged_options[key] = base_hash[key] }

  merged_options
end

def mock_registry_properties
  mock_cloud_options['properties']['registry']
end

def mock_registry
  registry = double('registry',
                    endpoint: mock_registry_properties['endpoint'],
                    user: mock_registry_properties['user'],
                    password: mock_registry_properties['password'])
  registry
end

def mock_cloud(options = nil, api_version = 1)
  Bosh::AzureCloud::Cloud.new(options || mock_cloud_options['properties'], api_version)
end

def time_measure
  start = Time.new
  yield
  Time.new - start
end

def run_in_new_process
  fork do
    yield
  end
end

class MockTelemetryManager
  def monitor(*)
    yield
  end
end

RSpec.configure do |config|
  config.before do
    logger = Logger.new('/dev/null')
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
    allow(logger).to receive(:set_request_id).with(MOCK_REQUEST_ID)
    RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 500
  end
end
