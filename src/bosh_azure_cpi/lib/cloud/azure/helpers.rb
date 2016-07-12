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
          AZURE_RESOUCE_PROVIDER_GROUP            => '2016-06-01',
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

    EPHEMERAL_DISK_NAME       = 'ephemeral-disk'
    AZURE_SCSI_HOST_DEVICE_ID = '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}'

    AZURE_MAX_RETRY_COUNT     = 10

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
      azure_client = Azure::Storage::Client.create(storage_account_name: storage_account[:name], storage_access_key: storage_account[:key])

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

      cloud_error('Azure CPI minimum disk size is 1 GB') if size < 1024
      cloud_error('Azure CPI maximum disk size is 1023 GB') if size > 1023 * 1024
    end

    def is_debug_mode(azure_properties)
      debug_mode = false
      debug_mode = azure_properties['debug_mode'] unless azure_properties['debug_mode'].nil?
      debug_mode
    end

    # https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-sizes/
    # size: The default ephemeral disk size for the instance type
    #   Reference Azure temporary disk size as the ephemeral disk size
    #   If the size is less than 30 GB, CPI uses 30 GB because the space may not be enough. You can find the temporary disk size in the comment if it is less than 30 GB
    #   If the size is larger than 1,023 GB, CPI uses 1,023 GB because max data disk size is 1,023 GB on Azure. You can find the temporary disk size in the comment if it is larger than 1,023 GB
    # count: The maximum number of data disks for the instance type
    #   The maximum number of data disks on Azure for now is 64. Set it to 64 if instance_type cannot be found in case a new instance type is supported in future
    class DiskInfo
      INSTANCE_TYPE_DISK_MAPPING = {
        # A-series
        'STANDARD_A0'  => [30, 1], # 20 GB
        'STANDARD_A1'  => [70, 2],
        'STANDARD_A2'  => [135, 4],
        'STANDARD_A3'  => [285, 8],
        'STANDARD_A4'  => [605, 16],
        'STANDARD_A5'  => [135, 4],
        'STANDARD_A6'  => [285, 8],
        'STANDARD_A7'  => [605, 16],
        'STANDARD_A8'  => [382, 16],
        'STANDARD_A9'  => [382, 16],
        'STANDARD_A10' => [382, 16],
        'STANDARD_A11' => [382, 16],

        # D-series
        'STANDARD_D1'  => [50, 2],
        'STANDARD_D2'  => [100, 4],
        'STANDARD_D3'  => [200, 8],
        'STANDARD_D4'  => [400, 16],
        'STANDARD_D11' => [100, 4],
        'STANDARD_D12' => [200, 8],
        'STANDARD_D13' => [400, 16],
        'STANDARD_D14' => [800, 32],

        # Dv2-series
        'STANDARD_D1_V2'  => [50, 2],
        'STANDARD_D2_V2'  => [100, 4],
        'STANDARD_D3_V2'  => [200, 8],
        'STANDARD_D4_V2'  => [400, 16],
        'STANDARD_D5_V2'  => [800, 32],
        'STANDARD_D11_V2' => [100, 4],
        'STANDARD_D12_V2' => [200, 8],
        'STANDARD_D13_V2' => [400, 16],
        'STANDARD_D14_V2' => [800, 32],
        'STANDARD_D15_V2' => [1023, 40], # 1024 GB

        # DS-series
        'STANDARD_DS1'  => [30, 2], # 7 GB
        'STANDARD_DS2'  => [30, 4], # 14 GB
        'STANDARD_DS3'  => [30, 8], # 28 GB
        'STANDARD_DS4'  => [56, 16],
        'STANDARD_DS11' => [28, 4],
        'STANDARD_DS12' => [56, 8],
        'STANDARD_DS13' => [112, 16],
        'STANDARD_DS14' => [224, 32],

        # DSv2-series
        'STANDARD_DS1_V2'  => [30, 2], # 7 GB
        'STANDARD_DS2_V2'  => [30, 4], # 14 GB
        'STANDARD_DS3_V2'  => [30, 8], # 28 GB
        'STANDARD_DS4_V2'  => [56, 16],
        'STANDARD_DS5_V2'  => [112, 32],
        'STANDARD_DS11_V2' => [28, 4],
        'STANDARD_DS12_V2' => [56, 8],
        'STANDARD_DS13_V2' => [112, 16],
        'STANDARD_DS14_V2' => [224, 32],
        'STANDARD_DS15_V2' => [280, 40],

        # F-series
        'STANDARD_F1'  => [30, 2], # 16 GB
        'STANDARD_F2'  => [32, 4],
        'STANDARD_F4'  => [64, 8],
        'STANDARD_F8'  => [128, 16],
        'STANDARD_F16' => [256, 32],

        # Fs-series
        'STANDARD_F1S'  => [30, 2], # 4 GB
        'STANDARD_F2S'  => [30, 4], # 8 GB
        'STANDARD_F4S'  => [30, 8], # 16 GB
        'STANDARD_F8S'  => [32, 16],
        'STANDARD_F16S' => [64, 32],

        # G-series
        'STANDARD_G1'  => [384, 4],
        'STANDARD_G2'  => [768, 8],
        'STANDARD_G3'  => [1023, 16], # 1,536 GB
        'STANDARD_G4'  => [1023, 32], # 3,072 GB
        'STANDARD_G5'  => [1023, 64], # 6,144 GB

        # Gs-series
        'STANDARD_GS1'  => [56, 4],
        'STANDARD_GS2'  => [112, 8],
        'STANDARD_GS3'  => [224, 16],
        'STANDARD_GS4'  => [448, 32],
        'STANDARD_GS5'  => [896, 64]
      }

      attr_reader :size, :count

      def self.default
        self.new(30, 64)
      end

      def self.for(instance_type)
        values = INSTANCE_TYPE_DISK_MAPPING[instance_type.upcase]
        DiskInfo.new(*values) if values
      end

      def initialize(size, count)
        @size = size
        @count = count
      end

      def size_in_mb
        @size * 1024
      end
    end

    private

    def validate_azure_stack_options(azure_properties)
      missing_keys = []
      missing_keys << "azure_stack_domain" if azure_properties['azure_stack_domain'].nil?
      missing_keys << "azure_stack_authentication" if azure_properties['azure_stack_authentication'].nil?
      raise ArgumentError, "missing configuration parameters for AzureStack > #{missing_keys.join(', ')}" unless missing_keys.empty?
    end
  end
end
