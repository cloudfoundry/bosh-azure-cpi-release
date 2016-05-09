module Bosh::AzureCloud
  module Helpers

    AZURE_RESOUCE_PROVIDER_COMPUTER         = 'crp'
    AZURE_RESOUCE_PROVIDER_NETWORK          = 'nrp'
    AZURE_RESOUCE_PROVIDER_STORAGE          = 'srp'
    AZURE_RESOUCE_PROVIDER_GROUP            = 'rp'
    AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY  = 'ad'

    AZURE_ENVIRONMENTS = {
      'AzureCloud' => {
        'resourceManagerEndpointUrl' => 'https://management.azure.com/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.com',
        'apiVersion' => {
          AZURE_RESOUCE_PROVIDER_COMPUTER         => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_NETWORK          => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_STORAGE          => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_GROUP            => '2015-01-01',
          AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY  => '2015-05-01-preview'
        }
      },
      'AzureChinaCloud' => {
        'resourceManagerEndpointUrl' => 'https://management.chinacloudapi.cn/',
        'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
        'apiVersion' => {
          AZURE_RESOUCE_PROVIDER_COMPUTER         => '2015-06-15',
          AZURE_RESOUCE_PROVIDER_NETWORK          => '2015-06-15',
          AZURE_RESOUCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOUCE_PROVIDER_GROUP            => '2015-06-15',
          AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      },
      'AzureStack' => {
        'resourceManagerEndpointUrl' => 'https://azurestack.local-api/',
        'apiVersion' => {
          AZURE_RESOUCE_PROVIDER_COMPUTER         => '2015-06-15',
          AZURE_RESOUCE_PROVIDER_NETWORK          => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_STORAGE          => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_GROUP            => '2015-05-01-preview',
          AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY  => '2015-05-01-preview'
        }
      }
    }

    EPHEMERAL_DISK_NAME = 'ephemeral-disk'

    ##
    # Raises CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [Exception] exception Exception to be logged (optional)
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    ## Encode all values in metadata to string.
    ## Add a tag user-agent, value is bosh.
    # @param [Hash] metadata
    # @return [Hash]
    def encode_metadata(metadata)
      ret = {}
      metadata.each do |key, value|
        ret[key] = value.to_s
      end
      ret
    end

    def generate_instance_id(storage_account_name, uuid)
      "#{storage_account_name}-#{uuid}"
    end

    def get_storage_account_name_from_instance_id(instance_id)
      ret = instance_id.match('^([^-]*)-(.*)$')
      cloud_error("Invalid instance id #{instance_id}") if ret.nil?
      return ret[1]
    end

    def validate_disk_caching(caching)
      if caching != 'None' && caching != 'ReadOnly' && caching != 'ReadWrite'
        cloud_error("Unknown disk caching #{caching}")
      end
    end

    def ignore_exception
      begin
        yield
      rescue
      end
    end

    def get_arm_endpoint(azure_properties)
      if azure_properties['environment'] == 'AzureStack'
        validate_azure_stack_options(azure_properties)
        domain = azure_properties['azure_stack_domain']
        "https://api.#{domain}"
      else
        AZURE_ENVIRONMENTS[azure_properties['environment']]['resourceManagerEndpointUrl']
      end
    end

    def get_token_resource(azure_properties)
      AZURE_ENVIRONMENTS[azure_properties['environment']]['resourceManagerEndpointUrl']
    end

    def get_azure_authentication_endpoint_and_api_version(azure_properties)
      url = nil
      api_version = get_api_version(azure_properties, AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY)
      if azure_properties['environment'] == 'AzureStack'
        validate_azure_stack_options(azure_properties)
        domain = azure_properties['azure_stack_domain']

        if azure_properties['azure_stack_authentication']  == 'AzureStack'
          url = "https://#{domain}/oauth2/token"
        elsif azure_properties['azure_stack_authentication']  == 'AzureStackAD'
          url = "https://#{domain}/#{azure_properties['tenant_id']}/oauth2/token"
        else
          url = "#{AZURE_ENVIRONMENTS['AzureCloud']['activeDirectoryEndpointUrl']}/#{azure_properties['tenant_id']}/oauth2/token"
          api_version = AZURE_ENVIRONMENTS['AzureCloud']['apiVersion'][AZURE_RESOUCE_PROVIDER_ACTIVEDIRECTORY]
        end
      else
        url = "#{AZURE_ENVIRONMENTS[azure_properties['environment']]['activeDirectoryEndpointUrl']}/#{azure_properties['tenant_id']}/oauth2/token"
      end

      return url, api_version
    end

    def initialize_azure_storage_client(storage_account, service = 'blob')
      azure_client = Azure.client(storage_account_name: storage_account[:name], storage_access_key: storage_account[:key])

      case service
        when 'blob'
          if storage_account[:storage_blob_host].end_with?('/')
            azure_client.storage_blob_host  = storage_account[:storage_blob_host].chop
          else
            azure_client.storage_blob_host  = storage_account[:storage_blob_host]
          end
        when 'table'
          if storage_account[:storage_table_host].nil?
            cloud_error("The storage account `#{storage_account[:name]}' does not support table")
          end

          if storage_account[:storage_table_host].end_with?('/')
            azure_client.storage_table_host = storage_account[:storage_table_host].chop
          else
            azure_client.storage_table_host = storage_account[:storage_table_host]
          end
        else
          cloud_error("No support for the storage service: `#{service}'")
      end

      azure_client
    end

    def get_api_version(azure_properties, resource_provider)
      AZURE_ENVIRONMENTS[azure_properties['environment']]['apiVersion'][resource_provider]
    end

    def validate_disk_size(size)
      raise ArgumentError, 'disk size needs to be an integer' unless size.kind_of?(Integer)

      cloud_error('Azure CPI minimum disk size is 1 GiB') if size < 1024
      cloud_error('Azure CPI maximum disk size is 1 TiB') if size > 1024 * 1000
    end

    private

    def validate_azure_stack_options(azure_properties)
      missing_keys = []
      missing_keys << "azure_stack_domain" unless azure_properties.has_key?('azure_stack_domain')
      missing_keys << "azure_stack_authentication" unless azure_properties.has_key?('azure_stack_authentication')
      raise ArgumentError, "missing configuration parameters for AzureStack > #{missing_keys.join(', ')}" unless missing_keys.empty?
    end
  end
end
