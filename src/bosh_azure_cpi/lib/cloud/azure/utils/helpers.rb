# frozen_string_literal: true

module Bosh::AzureCloud
  module Helpers
    AZURE_RESOURCE_PROVIDER_COMPUTE          = 'crp'
    AZURE_RESOURCE_PROVIDER_NETWORK          = 'nrp'
    AZURE_RESOURCE_PROVIDER_STORAGE          = 'srp'
    AZURE_RESOURCE_PROVIDER_GROUP            = 'rp'
    AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  = 'ad'

    ENVIRONMENT_AZURECLOUD        = 'AzureCloud'
    ENVIRONMENT_AZURECHINACLOUD   = 'AzureChinaCloud'
    ENVIRONMENT_AZUREUSGOVERNMENT = 'AzureUSGovernment'
    ENVIRONMENT_AZURESTACK        = 'AzureStack'
    ENVIRONMENT_AZUREGERMANCLOUD  = 'AzureGermanCloud'

    AZURE_ENVIRONMENTS = {
      ENVIRONMENT_AZURECLOUD => {
        'resourceManagerEndpointUrl' => 'https://management.azure.com/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.com',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE => '2018-04-01',
          AZURE_RESOURCE_PROVIDER_NETWORK => '2017-09-01',
          AZURE_RESOURCE_PROVIDER_STORAGE => '2017-10-01',
          AZURE_RESOURCE_PROVIDER_GROUP => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY => '2015-06-15'
        }
      },
      ENVIRONMENT_AZURECHINACLOUD => {
        'resourceManagerEndpointUrl' => 'https://management.chinacloudapi.cn/',
        'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE => '2018-04-01',
          AZURE_RESOURCE_PROVIDER_NETWORK => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE => '2017-10-01',
          AZURE_RESOURCE_PROVIDER_GROUP => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY => '2015-06-15'
        }
      },
      ENVIRONMENT_AZUREUSGOVERNMENT => {
        'resourceManagerEndpointUrl' => 'https://management.usgovcloudapi.net/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.us',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE => '2018-04-01',
          AZURE_RESOURCE_PROVIDER_NETWORK => '2017-09-01',
          AZURE_RESOURCE_PROVIDER_STORAGE => '2017-10-01',
          AZURE_RESOURCE_PROVIDER_GROUP => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY => '2015-06-15'
        }
      },
      ENVIRONMENT_AZURESTACK => {
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_NETWORK => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE => '2016-01-01',
          AZURE_RESOURCE_PROVIDER_GROUP => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY => '2015-06-15'
        }
      },
      ENVIRONMENT_AZUREGERMANCLOUD => {
        'resourceManagerEndpointUrl' => 'https://management.microsoftazure.de/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.de',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE => '2018-04-01',
          AZURE_RESOURCE_PROVIDER_NETWORK => '2017-09-01',
          AZURE_RESOURCE_PROVIDER_STORAGE => '2017-10-01',
          AZURE_RESOURCE_PROVIDER_GROUP => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY => '2015-06-15'
        }
      }
    }.freeze

    PROVISIONING_STATE_SUCCEEDED  = 'Succeeded'
    PROVISIONING_STATE_FAILED     = 'Failed'
    PROVISIONING_STATE_CANCELED   = 'Canceled'
    PROVISIONING_STATE_INPROGRESS = 'InProgress'

    # About user-agent:
    # For REST APIs, the value is "BOSH-AZURE-CPI".
    # For Azure resource tags, the value is "bosh".
    USER_AGENT_FOR_REST           = 'BOSH-AZURE-CPI'
    USER_AGENT_FOR_AZURE_RESOURCE = 'bosh'
    AZURE_TAGS                    = {
      'user-agent' => USER_AGENT_FOR_AZURE_RESOURCE
    }.freeze
    # ISV Tracking
    DEFAULT_ISV_TRACKING_GUID = '563bbbca-7944-4791-b9c6-8af0928114ac'

    AZURE_MAX_RETRY_COUNT = 10

    # sku
    SKU_TIER_STANDARD = 'Standard'
    SKU_TIER_PREMIUM  = 'Premium'

    # Storage Account
    STORAGE_ACCOUNT_TYPE_STANDARD_LRS    = 'Standard_LRS'
    STORAGE_ACCOUNT_TYPE_STANDARDSSD_LRS = 'StandardSSD_LRS'
    STORAGE_ACCOUNT_TYPE_PREMIUM_LRS     = 'Premium_LRS'
    STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1 = 'Storage'
    STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V2 = 'StorageV2'
    STEMCELL_STORAGE_ACCOUNT_TAGS = AZURE_TAGS.merge(
      'type' => 'stemcell'
    )
    DIAGNOSTICS_STORAGE_ACCOUNT_TAGS = AZURE_TAGS.merge(
      'type' => 'bootdiagnostics'
    )
    DISK_CONTAINER                    = 'bosh'
    STEMCELL_CONTAINER                = 'stemcell'
    STEMCELL_TABLE                    = 'stemcells'
    PUBLIC_ACCESS_LEVEL_BLOB          = 'blob'

    # Disk
    OS_DISK_PREFIX                  = 'bosh-os'
    DATA_DISK_PREFIX                = 'bosh-data'
    MANAGED_OS_DISK_PREFIX          = 'bosh-disk-os'
    MANAGED_DATA_DISK_PREFIX        = 'bosh-disk-data'
    MANAGED_CONFIG_DISK_PREFIX      = 'bosh-cfg-disk'
    EPHEMERAL_DISK_POSTFIX          = 'ephemeral-disk'
    STEMCELL_PREFIX                 = 'bosh-stemcell'
    LIGHT_STEMCELL_PREFIX           = 'bosh-light-stemcell'
    DISK_ID_TAG_PREFIX              = 'disk-id'
    LIGHT_STEMCELL_PROPERTY         = 'image'
    AZURE_SCSI_HOST_DEVICE_ID       = '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}'
    METADATA_FOR_MIGRATED_BLOB_DISK = {
      'user_agent' => USER_AGENT_FOR_AZURE_RESOURCE, # The key can't be user-agent because '-' is invalid for blob metadata
      'migrated' => 'true'
    }.freeze

    OS_TYPE_LINUX                               = 'linux'
    OS_TYPE_WINDOWS                             = 'windows'
    IMAGE_SIZE_IN_MB_LINUX                      = 3 * 1024
    IMAGE_SIZE_IN_MB_WINDOWS                    = 128 * 1024
    MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_LINUX   = 30
    MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_WINDOWS = 128

    # Lock
    CPI_LOCK_DIR                            = '/tmp/azure_cpi'
    CPI_LOCK_PREFIX                         = 'bosh-lock'
    CPI_LOCK_PREFIX_STORAGE_ACCOUNT         = "#{CPI_LOCK_PREFIX}-storage-account"
    CPI_LOCK_COPY_STEMCELL                  = "#{CPI_LOCK_PREFIX}-copy-stemcell"
    CPI_LOCK_CREATE_USER_IMAGE              = "#{CPI_LOCK_PREFIX}-create-user-image"
    CPI_LOCK_PREFIX_AVAILABILITY_SET        = "#{CPI_LOCK_PREFIX}-availability-set"
    CPI_LOCK_EVENT_HANDLER                  = "#{CPI_LOCK_PREFIX}-event-handler"

    # REST Connection Errors
    ERROR_OPENSSL_RESET           = 'SSL_connect'
    ERROR_SOCKET_UNKNOWN_HOSTNAME = 'Hostname not known'
    ERROR_CONNECTION_REFUSED      = 'Connection refused'

    # Length of instance id
    UUID_LENGTH                   = 36
    WINDOWS_VM_NAME_LENGTH        = 15

    # Azure Stack Authentication Type
    AZURESTACK_AUTHENTICATION_TYPE_AZUREAD           = 'AzureAD'
    AZURESTACK_AUTHENTICATION_TYPE_AZURECHINACLOUDAD = 'AzureChinaCloudAD'
    AZURESTACK_AUTHENTICATION_TYPE_ADFS              = 'ADFS'

    BOSH_JOBS_DIR = '/var/vcap/jobs'
    AZURESTACK_CA_CERT_RELATIVE_PATH            = 'azure_cpi/config/azure_stack_ca_cert.pem'
    SERVICE_PRINCIPAL_CERTIFICATE_RELATIVE_PATH = 'azure_cpi/config/service_principal_certificate.pem'

    CREDENTIALS_SOURCE_STATIC           = 'static'
    CREDENTIALS_SOURCE_MANAGED_IDENTITY = 'managed_identity'

    MANAGED_IDENTITY_ENDPOINT             = 'http://169.254.169.254/metadata/identity/oauth2/token'
    MANAGED_IDENTITY_ENDPOINT_API_VERSION = '2018-02-01'
    MANAGED_IDENTITY_TYPE_SYSTEM_ASSIGNED = 'SystemAssigned'
    MANAGED_IDENTITY_TYPE_USER_ASSIGNED   = 'UserAssigned'

    # Availability Zones
    AVAILABILITY_ZONES = %w[1 2 3].freeze

    # Telemetry
    CPI_EVENTS_DIR                        = '/tmp/azure_cpi_events'
    CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP = '/tmp/azure_cpi_events_last_update'
    CPI_TELEMETRY_LOG_FILE                = '/tmp/azure_cpi_telemetry.log'

    # Cache
    STORAGE_ACCOUNT_NAME_CACHE            = '/tmp/azure_cpi_storage_account_name_cache'

    ##
    # Raises CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [Exception] exception Exception to be logged (optional)
    def cloud_error(message, exception = nil)
      @logger&.error(message)
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    ## Encode all values in metadata to string.
    # @param [Hash] metadata
    # @return [Hash]
    def encode_metadata(metadata)
      ret = {}
      metadata.each do |key, value|
        ret[key] = value.to_s
      end
      ret
    end

    def validate_disk_caching(caching)
      valid_caching = %w[None ReadOnly ReadWrite]
      cloud_error("Unknown disk caching #{caching}") unless valid_caching.include?(caching)
    end

    def ignore_exception(error = Exception)
      yield
    rescue error
    end

    def bosh_jobs_dir
      # When creating bosh director, CPI uses the environment variable BOSH_JOBS_DIR as bosh_jobs_dir,
      # which is set to a local path (~/.bosh_init for bosh-init and ~/.bosh for bosh cli v2).
      # Otherwise, CPI uses /var/vcap/jobs/ as bosh_jobs_dir.
      ENV['BOSH_JOBS_DIR'].nil? ? BOSH_JOBS_DIR : ENV['BOSH_JOBS_DIR']
    end

    def get_arm_endpoint(azure_config)
      if azure_config.environment == ENVIRONMENT_AZURESTACK
        "https://#{azure_config.azure_stack.endpoint_prefix}.#{azure_config.azure_stack.domain}"
      else
        AZURE_ENVIRONMENTS[azure_config.environment]['resourceManagerEndpointUrl']
      end
    end

    def get_token_resource(azure_config)
      if azure_config.environment == ENVIRONMENT_AZURESTACK
        azure_config.azure_stack.resource
      else
        AZURE_ENVIRONMENTS[azure_config.environment]['resourceManagerEndpointUrl']
      end
    end

    def get_azure_authentication_endpoint_and_api_version(azure_config)
      url = nil
      api_version = get_api_version(azure_config, AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY)
      if azure_config.environment == ENVIRONMENT_AZURESTACK
        domain = azure_config.azure_stack.domain
        authentication = azure_config.azure_stack.authentication

        if authentication == AZURESTACK_AUTHENTICATION_TYPE_AZUREAD
          url = "#{AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECLOUD]['activeDirectoryEndpointUrl']}/#{azure_config.tenant_id}/oauth2/token"
          api_version = AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECLOUD]['apiVersion'][AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY]
        elsif authentication == AZURESTACK_AUTHENTICATION_TYPE_AZURECHINACLOUDAD
          url = "#{AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECHINACLOUD]['activeDirectoryEndpointUrl']}/#{azure_config.tenant_id}/oauth2/token"
          api_version = AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECHINACLOUD]['apiVersion'][AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY]
        elsif authentication == AZURESTACK_AUTHENTICATION_TYPE_ADFS
          url = "https://adfs.#{domain}/adfs/oauth2/token"
        else
          cloud_error("No support for the AzureStack authentication: '#{authentication}'")
        end
      else
        url = "#{AZURE_ENVIRONMENTS[azure_config.environment]['activeDirectoryEndpointUrl']}/#{azure_config.tenant_id}/oauth2/token"
      end

      [url, api_version]
    end

    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-linux-vm-access-arm
    def get_managed_identity_endpoint_and_version
      [MANAGED_IDENTITY_ENDPOINT, MANAGED_IDENTITY_ENDPOINT_API_VERSION]
    end

    def get_service_principal_certificate_path
      "#{bosh_jobs_dir}/#{SERVICE_PRINCIPAL_CERTIFICATE_RELATIVE_PATH}"
    end

    def get_storage_account_name_from_cache
      return "" unless File.file?(STORAGE_ACCOUNT_NAME_CACHE)
      File.open(STORAGE_ACCOUNT_NAME_CACHE, 'r').read.strip
    end

    def set_storage_account_name_to_cache(storage_account_name)
      File.open(STORAGE_ACCOUNT_NAME_CACHE, 'w') { |file| file.write(storage_account_name) }
    end

    def remove_storage_account_name_cache
      File.delete(STORAGE_ACCOUNT_NAME_CACHE) if File.exist?(STORAGE_ACCOUNT_NAME_CACHE)
    end

    # https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-certificate-credentials
    def get_jwt_assertion(authentication_endpoint, client_id)
      certificate_path = get_service_principal_certificate_path
      certificate_data = File.read(certificate_path)
      @logger.info("Reading the certificate from '#{certificate_path}'")
      cert = OpenSSL::X509::Certificate.new(certificate_data)
      thumbprint = OpenSSL::Digest::SHA1.new(cert.to_der).to_s
      @logger.debug("The certificate thumbprint is '#{thumbprint}'")
      header = {
        "alg": 'RS256',
        "typ": 'JWT',
        "x5t": Base64.urlsafe_encode64([thumbprint].pack('H*'))
      }
      payload = {
        "aud": authentication_endpoint,
        "exp": (Time.new + 3600).strftime('%s'),
        "iss": client_id,
        "jti": SecureRandom.uuid,
        "nbf": (Time.new - 90).strftime('%s'),
        "sub": client_id
      }
      rsa_private = OpenSSL::PKey::RSA.new(certificate_data)
      JWT.encode(payload, rsa_private, 'RS256', header)
    rescue StandardError => e
      cloud_error("Failed to get the jwt assertion: #{e.inspect}\n#{e.backtrace.join("\n")}")
    end

    def initialize_azure_storage_client(storage_account, azure_config)
      options = {
        storage_account_name: storage_account[:name],
        storage_access_key: storage_account[:key],
        storage_dns_suffix: URI.parse(storage_account[:storage_blob_host]).host.split('.')[2..-1].join('.'),
        user_agent_prefix: USER_AGENT_FOR_REST
      }
      options[:ca_file] = get_ca_cert_path if azure_config.environment == ENVIRONMENT_AZURESTACK

      Azure::Storage::Client.create(options)
    end

    def get_ca_cert_path
      "#{bosh_jobs_dir}/#{AZURESTACK_CA_CERT_RELATIVE_PATH}"
    end

    def get_api_version(azure_config, resource_provider)
      AZURE_ENVIRONMENTS[azure_config.environment]['apiVersion'][resource_provider]
    end

    def validate_disk_size(size)
      validate_disk_size_type(size)

      cloud_error('Azure CPI minimum disk size is 1 GiB') if size < 1024
    end

    def validate_disk_size_type(size)
      raise ArgumentError, "The disk size needs to be an integer. The current value is '#{size}'." unless size.is_a?(Integer)
    end

    def is_debug_mode(azure_config)
      azure_config.is_debug_mode
    end

    def merge_storage_common_options(options = {})
      options[:request_id] = SecureRandom.uuid
      options
    end

    # https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-sizes/
    # size: The default ephemeral disk size for the instance type
    #   Reference Azure temporary disk size as the ephemeral disk size
    #   If the size is less than 30 GiB, CPI uses 30 GiB because the space may not be enough. You can find the temporary disk size in the comment if it is less than 30 GiB
    #   If the size is larger than 1,000 GiB, CPI uses 1,000 GiB because it is not expected to use such a large ephemeral disk in CF currently. You can find the temporary disk size in the comment if it is larger than 1,000 GiB
    # count: The maximum number of data disks for the instance type
    #   The maximum number of data disks on Azure for now is 64. Set it to 64 if instance_type cannot be found in case a new instance type is supported in future
    class DiskInfo
      INSTANCE_TYPE_DISK_MAPPING = {
        # A-series
        'STANDARD_A0' => [30, 1], # 20 GiB
        'STANDARD_A1' => [70, 2],
        'STANDARD_A2' => [135, 4],
        'STANDARD_A3' => [285, 8],
        'STANDARD_A4' => [605, 16],
        'STANDARD_A5' => [135, 4],
        'STANDARD_A6' => [285, 8],
        'STANDARD_A7' => [605, 16],
        'STANDARD_A8' => [382, 32],
        'STANDARD_A9' => [382, 64],
        'STANDARD_A10' => [382, 32],
        'STANDARD_A11' => [382, 64],

        # Av2-series
        'STANDARD_A1_V2' => [30, 2], # 10 GiB
        'STANDARD_A2_V2' => [30, 4], # 20 GiB
        'STANDARD_A4_V2' => [40, 8],
        'STANDARD_A8_V2' => [80, 16],
        'STANDARD_A2M_V2' => [30, 4], # 20 GiB
        'STANDARD_A4M_V2' => [40, 8],
        'STANDARD_A8M_V2' => [80, 16],

        # D-series
        'STANDARD_D1' => [50, 4],
        'STANDARD_D2' => [100, 8],
        'STANDARD_D3' => [200, 16],
        'STANDARD_D4' => [400, 32],
        'STANDARD_D11' => [100, 8],
        'STANDARD_D12' => [200, 16],
        'STANDARD_D13' => [400, 32],
        'STANDARD_D14' => [800, 64],

        # Dv2-series
        'STANDARD_D1_V2' => [50, 4],
        'STANDARD_D2_V2' => [100, 8],
        'STANDARD_D3_V2' => [200, 16],
        'STANDARD_D4_V2' => [400, 32],
        'STANDARD_D5_V2' => [800, 64],
        'STANDARD_D11_V2' => [100, 8],
        'STANDARD_D12_V2' => [200, 16],
        'STANDARD_D13_V2' => [400, 32],
        'STANDARD_D14_V2' => [800, 64],
        'STANDARD_D15_V2' => [1000, 64],

        # DS-series
        'STANDARD_DS1' => [30, 4], # 7 GiB
        'STANDARD_DS2' => [30, 8], # 14 GiB
        'STANDARD_DS3' => [30, 16], # 28 GiB
        'STANDARD_DS4' => [56, 32],
        'STANDARD_DS11' => [28, 8],
        'STANDARD_DS12' => [56, 16],
        'STANDARD_DS13' => [112, 32],
        'STANDARD_DS14' => [224, 64],

        # DSv2-series
        'STANDARD_DS1_V2' => [30, 4], # 7 GiB
        'STANDARD_DS2_V2' => [30, 8], # 14 GiB
        'STANDARD_DS3_V2' => [30, 16], # 28 GiB
        'STANDARD_DS4_V2' => [56, 32],
        'STANDARD_DS5_V2' => [112, 64],
        'STANDARD_DS11_V2' => [28, 8],
        'STANDARD_DS12_V2' => [56, 16],
        'STANDARD_DS13_V2' => [112, 32],
        'STANDARD_DS14_V2' => [224, 64],
        'STANDARD_DS15_V2' => [280, 64],

        # F-series
        'STANDARD_F1' => [30, 4], # 16 GiB
        'STANDARD_F2' => [32, 8],
        'STANDARD_F4' => [64, 16],
        'STANDARD_F8' => [128, 32],
        'STANDARD_F16' => [256, 64],

        # Fs-series
        'STANDARD_F1S' => [30, 4], # 4 GiB
        'STANDARD_F2S' => [30, 8], # 8 GiB
        'STANDARD_F4S' => [30, 16], # 16 GiB
        'STANDARD_F8S' => [32, 32],
        'STANDARD_F16S' => [64, 64],

        # G-series
        'STANDARD_G1' => [384, 8],
        'STANDARD_G2' => [768, 16],
        'STANDARD_G3' => [1000, 32], # 1536 GiB
        'STANDARD_G4' => [1000, 64], # 3072 GiB
        'STANDARD_G5' => [1000, 64], # 6144 GiB

        # Gs-series
        'STANDARD_GS1' => [56, 8],
        'STANDARD_GS2' => [112, 16],
        'STANDARD_GS3' => [224, 32],
        'STANDARD_GS4' => [448, 64],
        'STANDARD_GS5' => [896, 64],

        # Ls-series
        'STANDARD_L4S' => [678, 16],
        'STANDARD_L8S' => [1000, 32], # 1388 GiB
        'STANDARD_L16S' => [1000, 64], # 2807 GiB
        'STANDARD_L32S' => [1000, 64], # 5630 GiB

        # M-series
        'STANDARD_M64MS' => [1000, 64], # 2048 GiB
        'STANDARD_M128S' => [1000, 64], # 4096 GiB

        # NV-series
        'STANDARD_NV6' => [380, 8],
        'STANDARD_NV12' => [680, 16],
        'STANDARD_NV24' => [1000, 32], # 1440 GiB

        # NC-series
        'STANDARD_NC6' => [380, 24],
        'STANDARD_NC12' => [680, 48],
        'STANDARD_NC24' => [1000, 64], # 1440 GiB
        'STANDARD_NC24R' => [1000, 64], # 1440 GiB

        # H-series
        'STANDARD_H8' => [1000, 32],
        'STANDARD_H16' => [1000, 64], # 2000 GiB
        'STANDARD_H8M' => [1000, 32],
        'STANDARD_H16M' => [1000, 64], # 2000 GiB
        'STANDARD_H16R' => [1000, 64], # 2000 GiB
        'STANDARD_H16MR' => [1000, 64] # 2000 GiB
      }.freeze

      attr_reader :size, :count

      def self.for(instance_type)
        values = INSTANCE_TYPE_DISK_MAPPING[instance_type.upcase]
        if values
          DiskInfo.new(*values)
        else
          DiskInfo.new(30, 64)
        end
      end

      def initialize(size, count)
        @size = size
        @count = count
      end
    end

    # Stemcell information
    # * +:uri+         - String. uri of the blob stemcell, e.g. "https://<storage-account-name>.blob.core.windows.net/stemcell/bosh-stemcell-82817f34-ae10-4cfe-8ca8-b18d18ee5cdd.vhd"
    #                            id of the image stemcell, e.g. "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Compute/images/bosh-stemcell-d42a792c-db7a-45a6-8132-e03c863c9f01-Standard_LRS-southeastasia"
    # * +:os_type+     - String. os type of the stemcell, e.g. "linux"
    # * +:name+        - String. name of the stemcell, e.g. "bosh-azure-hyperv-ubuntu-trusty-go_agent"
    # * +:version      - String. version of the stemcell, e.g. "2972"
    # * +:image_size   - Integer. size in MiB of the image.
    #                             For a normal stemcell, the value should be the size of root.vhd.
    #                             For a light stemcell, the value should be the size of the platform image.
    # * +:image        - Hash. It is nil when the stemcell is not a light stemcell.
    # *   +publisher+    - String. The publisher of the platform image.
    # *   +offer+        - String. The offer from the publisher.
    # *   +sku+          - String. The sku of the publisher's offer.
    # *   +version+      - String. The version of the sku.
    class StemcellInfo
      attr_reader :uri, :metadata, :os_type, :name, :version, :image_size, :image

      def initialize(uri, metadata)
        @uri = uri
        @metadata = metadata
        @os_type = @metadata['os_type'].nil? ? 'linux' : @metadata['os_type'].downcase
        @name = @metadata['name']
        @version = @metadata['version']
        @image_size = if @metadata['disk'].nil?
                        is_windows? ? IMAGE_SIZE_IN_MB_WINDOWS : IMAGE_SIZE_IN_MB_LINUX
                      else
                        @metadata['disk'].to_i
                      end
        @image = @metadata['image']
      end

      def is_light_stemcell?
        !@image.nil?
      end

      def is_windows?
        @os_type == OS_TYPE_WINDOWS
      end

      # This will be used when creating VMs
      # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
      #
      def image_reference
        return nil unless is_light_stemcell?

        {
          'publisher' => @image['publisher'],
          'offer' => @image['offer'],
          'sku' => @image['sku'],
          'version' => @image['version']
        }
      end
    end

    def get_os_disk_size(root_disk_size, stemcell_info, use_root_disk)
      disk_size = nil
      image_size = stemcell_info.image_size
      unless root_disk_size.nil?
        validate_disk_size_type(root_disk_size)
        if root_disk_size < image_size
          @logger.warn("root_disk.size '#{root_disk_size}' MiB is smaller than the default OS disk size '#{image_size}' MiB. root_disk.size is ignored and use '#{image_size}' MiB as root disk size.")
          root_disk_size = image_size
        end
        disk_size = (root_disk_size / 1024.0).ceil
        validate_disk_size(disk_size * 1024)
      end

      # When using OS disk to store the ephemeral data and root_disk.size is not set, CPI will resize the OS disk size.
      # For Linux,   the size of the VHD in the stemcell is 3   GiB. CPI will resize it to the high value between the minimum disk size and 30  GiB;
      # For Windows, the size of the VHD in the stemcell is 128 GiB. CPI will resize it to the high value between the minimum disk size and 128 GiB.
      if disk_size.nil? && use_root_disk
        minimum_required_disk_size = stemcell_info.is_windows? ? MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_WINDOWS : MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_LINUX
        disk_size = (image_size / 1024.0).ceil < minimum_required_disk_size ? minimum_required_disk_size : (image_size / 1024.0).ceil
      end
      disk_size
    end

    # File lock, used in inter process communication
    # When the lock is acquired, the process will execute the code in the block
    #
    # @param [String] lock_name   - lock name
    # @param [Constants] mode     - lock mode, a logical 'or' of the values in LOCK_EX, LOCK_NB, LOCK_SH. See detail in http://ruby-doc.org/core-2.4.2/File.html#method-i-flock
    # @return - return value of the block
    #
    def flock(lock_name, mode)
      file_path = "#{CPI_LOCK_DIR}/#{lock_name}"
      file = File.open(file_path, File::RDWR | File::CREAT, 0o644)
      success = file.flock(mode)
      if success
        begin
          return yield
        ensure
          file.flock(File::LOCK_UN)
        end
      end
    end

    def get_storage_account_type_by_instance_type(instance_type)
      support_premium_storage?(instance_type) ? STORAGE_ACCOUNT_TYPE_PREMIUM_LRS : STORAGE_ACCOUNT_TYPE_STANDARD_LRS
    end

    def support_premium_storage?(instance_type)
      instance_type = instance_type.downcase
      ((instance_type =~ /^standard_ds/) == 0) || # including DS and DSv2, e.g. Standard_DS1, Standard_DS1_v2
        ((instance_type =~ /^standard_d(\d)+s_v3/) == 0) ||
        ((instance_type =~ /^standard_gs/) == 0) ||
        ((instance_type =~ /^standard_b(\d)+s/) == 0) ||
        ((instance_type =~ /^standard_b(\d)+ms/) == 0) ||
        ((instance_type =~ /^standard_f(\d)+s/) == 0) ||
        ((instance_type =~ /^standard_e(\d)+s_v3/) == 0) ||
        ((instance_type =~ /^standard_e(\d)+is_v3/) == 0) ||
        ((instance_type =~ /^standard_l(\d)+s/) == 0)
    end

    def is_stemcell_storage_account?(tags)
      (STEMCELL_STORAGE_ACCOUNT_TAGS.to_a - tags.to_a).empty?
    end

    def is_ephemeral_disk?(name)
      name.end_with?(EPHEMERAL_DISK_POSTFIX)
    end

    def has_light_stemcell_property?(stemcell_properties)
      stemcell_properties.key?(LIGHT_STEMCELL_PROPERTY)
    end

    def is_light_stemcell_cid?(stemcell_cid)
      stemcell_cid.start_with?(LIGHT_STEMCELL_PREFIX)
    end

    # use timestamp and process id to generate a unique string for computer name of Windows
    #
    def generate_windows_computer_name
      prefix = Time.new.to_f
      prefix = prefix.to_s.delete('.')
      prefix = prefix.to_i.to_s(32) # example timestamp 1482829740.3734238 -> 'd5e883lv66u'
      suffix = Process.pid.to_s(32) # default max pid 65536, .to_s(32) -> '2000'
      padding_length = WINDOWS_VM_NAME_LENGTH - prefix.length - suffix.length
      if padding_length >= 0
        prefix + '0' * padding_length + suffix
      else
        @logger.warn('Length of generated string is longer than expected, so it is truncated. It may be not unique.')
        (prefix + suffix)[prefix.length + suffix.length - WINDOWS_VM_NAME_LENGTH, prefix.length + suffix.length] # get tail
      end
    end

    def validate_idle_timeout(idle_timeout_in_minutes)
      raise ArgumentError, 'idle_timeout_in_minutes needs to be an integer' unless idle_timeout_in_minutes.is_a?(Integer)

      cloud_error('Minimum idle_timeout_in_minutes is 4 minutes') if idle_timeout_in_minutes < 4
      cloud_error('Maximum idle_timeout_in_minutes is 30 minutes') if idle_timeout_in_minutes > 30
    end
  end
end
