$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'simplecov'
SimpleCov.start

require 'cloud/azure'
require 'json'
require 'net/http'

MOCK_AZURE_SUBSCRIPTION_ID = 'aa643f05-5b67-4d58-b433-54c2e9131a59'
MOCK_DEFAULT_STORAGE_ACCOUNT_NAME = '8853f441db154b438550a853'
MOCK_AZURE_STORAGE_ACCESS_KEY = '3e795106-5887-4342-8c73-338facbb09fa'
MOCK_RESOURCE_GROUP_NAME = '352ec9c1-6dd5-4a24-b11e-21bbe3d712ca'
MOCK_AZURE_TENANT_ID = 'e441d583-68c5-46b3-bf43-ab49c5f07fed'
MOCK_AZURE_CLIENT_ID = '62bd3eaa-e231-4e13-8baf-0e2cc8a898a1'
MOCK_AZURE_CLIENT_SECRET = '0e67d8fc-150e-4cc0-bbf3-087e6c4b9e2a'
MOCK_SSH_PUBLIC_KEY = 'bar'
MOCK_DEFAULT_SECURITY_GROUP = 'fake-default-nsg-name'

# Let us keep the least API versions here for unit tests.
AZURE_API_VERSION = '2015-06-15'
AZURE_RESOURCE_PROVIDER_COMPUTE = '2016-04-30-preview'
AZURE_RESOURCE_PROVIDER_GROUP = '2016-06-01'
AZURE_STACK_API_VERSION = '2015-05-01-preview'
AZURE_CHINA_API_VERSION = '2015-06-15'
AZURE_USGOV_API_VERSION = '2015-06-15'

ERROR_MSG_OPENSSL_RESET = 'Connection reset by peer - SSL_connect'

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
        'use_managed_disks' => false
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

def mock_azure_properties
  mock_cloud_options['properties']['azure']
end

def mock_azure_properties_merge(override_options)
  mock_cloud_options_merge(override_options, mock_azure_properties)
end

def mock_cloud_properties_merge(override_options)
  mock_cloud_options_merge(override_options, mock_cloud_options['properties'])
end

def mock_cloud_options_merge(override_options, base_hash = mock_cloud_options)
  merged_options = {}
  override_options ||= {}

  override_options.each do |key, value|
    if value.is_a? Hash
      merged_options[key] = mock_cloud_options_merge(override_options[key], base_hash[key])
    else
      merged_options[key] = value
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
    :endpoint => mock_registry_properties['endpoint'],
    :user     => mock_registry_properties['user'],
    :password => mock_registry_properties['password']
  )
  allow(Bosh::Cpi::RegistryClient).to receive(:new).and_return(registry)
  registry
end

def mock_cloud(options = nil)
  Bosh::AzureCloud::Cloud.new(options || mock_cloud_options['properties'])
end

RSpec.configure do |config|
  config.before do
    logger = Logger.new('/dev/null')
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
  end
end
