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
    ENVIRONMENT_AZUREGermanCloud  = 'AzureGermanCloud'

    AZURE_ENVIRONMENTS = {
      ENVIRONMENT_AZURECLOUD => {
        'resourceManagerEndpointUrl' => 'https://management.azure.com/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.com',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE          => '2016-04-30-preview',
          AZURE_RESOURCE_PROVIDER_NETWORK          => '2017-09-01',
          AZURE_RESOURCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_GROUP            => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      },
      ENVIRONMENT_AZURECHINACLOUD => {
        'resourceManagerEndpointUrl' => 'https://management.chinacloudapi.cn/',
        'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE          => '2016-04-30-preview',
          AZURE_RESOURCE_PROVIDER_NETWORK          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_GROUP            => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      },
      ENVIRONMENT_AZUREUSGOVERNMENT => {
        'resourceManagerEndpointUrl' => 'https://management.usgovcloudapi.net/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.com',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE          => '2016-04-30-preview',
          AZURE_RESOURCE_PROVIDER_NETWORK          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_GROUP            => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      },
      ENVIRONMENT_AZURESTACK => {
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_NETWORK          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_GROUP            => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      },
      ENVIRONMENT_AZUREGermanCloud => {
        'resourceManagerEndpointUrl' => 'https://management.microsoftazure.de/',
        'activeDirectoryEndpointUrl' => 'https://login.microsoftonline.de',
        'apiVersion' => {
          AZURE_RESOURCE_PROVIDER_COMPUTE          => '2016-04-30-preview',
          AZURE_RESOURCE_PROVIDER_NETWORK          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_STORAGE          => '2015-06-15',
          AZURE_RESOURCE_PROVIDER_GROUP            => '2016-06-01',
          AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY  => '2015-06-15'
        }
      }
    }

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
    }

    AZURE_MAX_RETRY_COUNT         = 10

    # Storage Account
    STORAGE_ACCOUNT_TYPE_STANDARD_LRS = 'Standard_LRS'
    STORAGE_ACCOUNT_TYPE_PREMIUM_LRS  = 'Premium_LRS'
    STEMCELL_STORAGE_ACCOUNT_TAGS     = AZURE_TAGS.merge({
      'type' => 'stemcell'
    })
    DISK_CONTAINER                    = 'bosh'
    STEMCELL_CONTAINER                = 'stemcell'
    STEMCELL_TABLE                    = 'stemcells'
    PUBLIC_ACCESS_LEVEL_BLOB          = "blob"

    # Disk
    OS_DISK_PREFIX                  = 'bosh-os'
    DATA_DISK_PREFIX                = 'bosh-data'
    MANAGED_OS_DISK_PREFIX          = 'bosh-disk-os'
    MANAGED_DATA_DISK_PREFIX        = 'bosh-disk-data'
    EPHEMERAL_DISK_POSTFIX          = 'ephemeral-disk'
    STEMCELL_PREFIX                 = 'bosh-stemcell'
    LIGHT_STEMCELL_PREFIX           = 'bosh-light-stemcell'
    DISK_ID_TAG_PREFIX              = 'disk-id'
    LIGHT_STEMCELL_PROPERTY         = 'image'
    AZURE_SCSI_HOST_DEVICE_ID       = '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}'
    METADATA_FOR_MIGRATED_BLOB_DISK = {
      "user_agent" => USER_AGENT_FOR_AZURE_RESOURCE, # The key can't be user-agent because '-' is invalid for blob metadata
      "migrated" => "true"
    }

    OS_TYPE_LINUX                               = 'linux'
    OS_TYPE_WINDOWS                             = 'windows'
    IMAGE_SIZE_IN_MB_LINUX                      = 3 * 1024
    IMAGE_SIZE_IN_MB_WINDOWS                    = 128 * 1024
    MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_LINUX   = 30
    MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_WINDOWS = 128

    # Lock
    CPI_LOCK_DIR                         = "/tmp/azure_cpi"
    CPI_LOCK_PREFIX                      = "bosh-lock"
    CPI_LOCK_CREATE_STORAGE_ACCOUNT      = "#{CPI_LOCK_PREFIX}-create-storage-account"
    CPI_LOCK_COPY_STEMCELL               = "#{CPI_LOCK_PREFIX}-copy-stemcell"
    CPI_LOCK_COPY_STEMCELL_TIMEOUT       = 180 # seconds
    CPI_LOCK_CREATE_USER_IMAGE           = "#{CPI_LOCK_PREFIX}-create-user-image"
    CPI_LOCK_PREFIX_AVAILABILITY_SET     = "#{CPI_LOCK_PREFIX}-availability-set"
    CPI_LOCK_DELETE                      = "#{CPI_LOCK_DIR}/DELETING-LOCKS"
    class LockError < Bosh::Clouds::CloudError; end
    class LockTimeoutError < LockError; end
    class LockNotFoundError < LockError; end
    class LockNotOwnedError < LockError; end

    # REST Connection Errors
    ERROR_OPENSSL_RESET           = 'SSL_connect'
    ERROR_SOCKET_UNKNOWN_HOSTNAME = 'Hostname not known'
    ERROR_CONNECTION_REFUSED      = 'Connection refused'

    # Length of instance id
    UUID_LENGTH                   = 36
    WINDOWS_VM_NAME_LENGTH        = 15

    # Azure Stack Authentication Type
    AZURESTACK_AUTHENTICATION_TYPE_AZURESTACK   = 'AzureStack'
    AZURESTACK_AUTHENTICATION_TYPE_AZURESTACKAD = 'AzureStackAD'
    AZURESTACK_AUTHENTICATION_TYPE_AZUREAD      = 'AzureAD'

    BOSH_JOBS_DIR = '/var/vcap/jobs'
    AZURESTACK_CA_FILE_RELATIVE_PATH = 'azure_cpi/config/azure_stack_ca_cert.pem'

    AVAILABILITY_ZONES = ['1', '2', '3']

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
      valid_caching = ['None', 'ReadOnly', 'ReadWrite']
      unless valid_caching.include?(caching)
        cloud_error("Unknown disk caching #{caching}")
      end
    end

    def ignore_exception(error = Exception)
      begin
        yield
      rescue error
      end
    end

    def get_arm_endpoint(azure_properties)
      if azure_properties['environment'] == ENVIRONMENT_AZURESTACK
        "https://#{azure_properties['azure_stack']['endpoint_prefix']}.#{azure_properties['azure_stack']['domain']}"
      else
        AZURE_ENVIRONMENTS[azure_properties['environment']]['resourceManagerEndpointUrl']
      end
    end

    def get_token_resource(azure_properties)
      if azure_properties['environment'] == ENVIRONMENT_AZURESTACK
        azure_properties['azure_stack']['resource']
      else
        AZURE_ENVIRONMENTS[azure_properties['environment']]['resourceManagerEndpointUrl']
      end
    end

    def get_azure_authentication_endpoint_and_api_version(azure_properties)
      url = nil
      api_version = get_api_version(azure_properties, AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY)
      if azure_properties['environment'] == ENVIRONMENT_AZURESTACK
        domain = azure_properties['azure_stack']['domain']
        authentication = azure_properties['azure_stack']['authentication']

        if authentication == AZURESTACK_AUTHENTICATION_TYPE_AZURESTACK
          url = "https://#{domain}/oauth2/token"
        elsif authentication == AZURESTACK_AUTHENTICATION_TYPE_AZURESTACKAD
          url = "https://#{domain}/#{azure_properties['tenant_id']}/oauth2/token"
        elsif authentication == AZURESTACK_AUTHENTICATION_TYPE_AZUREAD
          url = "#{AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECLOUD]['activeDirectoryEndpointUrl']}/#{azure_properties['tenant_id']}/oauth2/token"
          api_version = AZURE_ENVIRONMENTS[ENVIRONMENT_AZURECLOUD]['apiVersion'][AZURE_RESOURCE_PROVIDER_ACTIVEDIRECTORY]
        else
          cloud_error("No support for the AzureStack authentication: `#{authentication}'")
        end
      else
        url = "#{AZURE_ENVIRONMENTS[azure_properties['environment']]['activeDirectoryEndpointUrl']}/#{azure_properties['tenant_id']}/oauth2/token"
      end

      return url, api_version
    end

    def initialize_azure_storage_client(storage_account, azure_properties)
      options = {
        :storage_account_name => storage_account[:name],
        :storage_access_key   => storage_account[:key],
        :storage_dns_suffix   => URI.parse(storage_account[:storage_blob_host]).host.split(".")[2..-1].join("."),
        :user_agent_prefix    => USER_AGENT_FOR_REST
      }
      options[:ca_file] = get_ca_file_path if azure_properties['environment'] == ENVIRONMENT_AZURESTACK

      Azure::Storage::Client.create(options)
    end

    def get_ca_file_path
      # The environment variable BOSH_JOBS_DIR only exists when deploying BOSH director
      bosh_jobs_dir = ENV['BOSH_JOBS_DIR'].nil? ? BOSH_JOBS_DIR : ENV['BOSH_JOBS_DIR']
      "#{bosh_jobs_dir}/#{AZURESTACK_CA_FILE_RELATIVE_PATH}"
    end

    def get_api_version(azure_properties, resource_provider)
      AZURE_ENVIRONMENTS[azure_properties['environment']]['apiVersion'][resource_provider]
    end

    def validate_disk_size(size)
      validate_disk_size_type(size)

      cloud_error('Azure CPI minimum disk size is 1 GiB') if size < 1024
    end

    def validate_disk_size_type(size)
      raise ArgumentError, "The disk size needs to be an integer. The current value is `#{size}'." unless size.kind_of?(Integer)
    end

    def is_debug_mode(azure_properties)
      debug_mode = false
      debug_mode = azure_properties['debug_mode'] unless azure_properties['debug_mode'].nil?
      debug_mode
    end

    def merge_storage_common_options(options = {})
      options.merge!({ :request_id => SecureRandom.uuid })
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
        'STANDARD_A0'  => [30, 1], # 20 GiB
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

        # Av2-series
        'STANDARD_A1_V2'   => [30, 2], #10 GiB
        'STANDARD_A2_V2'   => [30, 4], #20 GiB
        'STANDARD_A4_V2'   => [40, 8],
        'STANDARD_A8_V2'   => [80, 16],
        'STANDARD_A2M_V2'  => [30, 4], #20 GiB
        'STANDARD_A4M_V2'  => [40, 8],
        'STANDARD_A8M_V2'  => [80, 16],

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
        'STANDARD_D15_V2' => [1000, 40],

        # DS-series
        'STANDARD_DS1'  => [30, 2], # 7 GiB
        'STANDARD_DS2'  => [30, 4], # 14 GiB
        'STANDARD_DS3'  => [30, 8], # 28 GiB
        'STANDARD_DS4'  => [56, 16],
        'STANDARD_DS11' => [28, 4],
        'STANDARD_DS12' => [56, 8],
        'STANDARD_DS13' => [112, 16],
        'STANDARD_DS14' => [224, 32],

        # DSv2-series
        'STANDARD_DS1_V2'  => [30, 2], # 7 GiB
        'STANDARD_DS2_V2'  => [30, 4], # 14 GiB
        'STANDARD_DS3_V2'  => [30, 8], # 28 GiB
        'STANDARD_DS4_V2'  => [56, 16],
        'STANDARD_DS5_V2'  => [112, 32],
        'STANDARD_DS11_V2' => [28, 4],
        'STANDARD_DS12_V2' => [56, 8],
        'STANDARD_DS13_V2' => [112, 16],
        'STANDARD_DS14_V2' => [224, 32],
        'STANDARD_DS15_V2' => [280, 40],

        # F-series
        'STANDARD_F1'  => [30, 2], # 16 GiB
        'STANDARD_F2'  => [32, 4],
        'STANDARD_F4'  => [64, 8],
        'STANDARD_F8'  => [128, 16],
        'STANDARD_F16' => [256, 32],

        # Fs-series
        'STANDARD_F1S'  => [30, 2], # 4 GiB
        'STANDARD_F2S'  => [30, 4], # 8 GiB
        'STANDARD_F4S'  => [30, 8], # 16 GiB
        'STANDARD_F8S'  => [32, 16],
        'STANDARD_F16S' => [64, 32],

        # G-series
        'STANDARD_G1'  => [384, 4],
        'STANDARD_G2'  => [768, 8],
        'STANDARD_G3'  => [1000, 16], # 1536 GiB
        'STANDARD_G4'  => [1000, 32], # 3072 GiB
        'STANDARD_G5'  => [1000, 64], # 6144 GiB

        # Gs-series
        'STANDARD_GS1'  => [56, 4],
        'STANDARD_GS2'  => [112, 8],
        'STANDARD_GS3'  => [224, 16],
        'STANDARD_GS4'  => [448, 32],
        'STANDARD_GS5'  => [896, 64],

        #Ls-series
        'STANDARD_L4S'  => [678, 8],
        'STANDARD_L8S'  => [1000, 16], # 1388 GiB
        'STANDARD_L16S' => [1000, 32], # 2807 GiB
        'STANDARD_L32S' => [1000, 64], # 5630 GiB

        #M-series
        'STANDARD_M64MS' => [1000, 32], # 2048 GiB
        'STANDARD_M128S' => [1000, 64], # 4096 GiB

        #NV-series
        'STANDARD_NV6'  => [380, 8],
        'STANDARD_NV12' => [680, 16],
        'STANDARD_NV24' => [1000, 32], # 1440 GiB

        #NC-series
        'STANDARD_NC6'   => [380, 8],
        'STANDARD_NC12'  => [680, 16],
        'STANDARD_NC24'  => [1000, 32], # 1440 GiB
        'STANDARD_NC24R' => [1000, 32], # 1440 GiB

        #H-series
        'STANDARD_8'    => [1000, 16],
        'STANDARD_16'   => [1000, 32], # 2000 GiB
        'STANDARD_8M'   => [1000, 16],
        'STANDARD_16M'  => [1000, 32], # 2000 GiB
        'STANDARD_16R'  => [1000, 32], # 2000 GiB
        'STANDARD_16MR' => [1000, 32]  # 2000 GiB
      }

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
        @os_type = @metadata['os_type'].nil? ? 'linux': @metadata['os_type'].downcase
        @name = @metadata['name']
        @version = @metadata['version']
        if @metadata['disk'].nil?
          @image_size = is_windows? ? IMAGE_SIZE_IN_MB_WINDOWS : IMAGE_SIZE_IN_MB_LINUX
        else
          @image_size = @metadata['disk'].to_i
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
          'offer'     => @image['offer'],
          'sku'       => @image['sku'],
          'version'   => @image['version']
        }
      end
    end

    def get_os_disk_size(root_disk_size, stemcell_info, use_root_disk)
      disk_size = nil
      image_size = stemcell_info.image_size
      unless root_disk_size.nil?
        validate_disk_size_type(root_disk_size)
        if root_disk_size < image_size
          @logger.warn("root_disk.size `#{root_disk_size}' MiB is smaller than the default OS disk size `#{image_size}' MiB. root_disk.size is ignored and use `#{image_size}' MiB as root disk size.")
          root_disk_size = image_size
        end
        disk_size = (root_disk_size/1024.0).ceil
        validate_disk_size(disk_size*1024)
      end

      # When using OS disk to store the ephemeral data and root_disk.size is not set, CPI will resize the OS disk size.
      # For Linux,   the size of the VHD in the stemcell is 3   GiB. CPI will resize it to the high value between the minimum disk size and 30  GiB;
      # For Windows, the size of the VHD in the stemcell is 128 GiB. CPI will resize it to the high value between the minimum disk size and 128 GiB.
      if disk_size.nil? && use_root_disk
        minimum_required_disk_size = stemcell_info.is_windows? ? MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_WINDOWS : MINIMUM_REQUIRED_OS_DISK_SIZE_IN_GB_LINUX
        disk_size = (image_size/1024.0).ceil < minimum_required_disk_size ? minimum_required_disk_size : (image_size/1024.0).ceil
      end
      disk_size
    end

    # File Mutex
    #
    # Example codes:
    #
    # expired = 60 # seconds
    # mutex = FileMutex.new('bosh-lock-example', logger, expired)
    #
    # begin
    #   if mutex.lock
    #     # When any exception occurs in do_something(), the mutex won't be unlocked, and other processes will timeout. This is by design.
    #     # Please note, the mutex should NOT be unlocked, because other processes will end mutex.wait and continue to use the shared resource if unlocked.
    #     # If your work is a long-running task,
    #     #   you need to call mutex.update() in do_something() to update the lock before it timeouts (60s in the example).
    #     do_something() 
    #     mutex.unlock
    #   else
    #     mutex.wait
    #   end
    # rescue => e
    #   mark_deleting_locks
    #   raise 'what action fails because of the lock error'
    # end
    #
    # NOTE:
    #   The difference between modified time and current time determines if timeout or not.
    #   So the actully time to wait may be longer than the time set by `expired`.
    #
    class FileMutex
      attr_reader :expired

      def initialize(lock_name, logger, expired = 60)
        @file_path = "#{CPI_LOCK_DIR}/#{lock_name}"
        @logger = logger
        @expired = expired
        @is_locked = false
      end

      def lock()
        begin
          mtime = File.mtime(@file_path)
        rescue Errno::ENOENT => e
          # lock file does not exist so we can try to lock
          begin
            fd = IO.sysopen(@file_path, Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT) # Using O_EXCL, creation fails if the file exists
            f = IO.open(fd)
            f.syswrite("#{Process.pid}")
            @logger.debug("The lock `#{@file_path}' is created by the process `#{Process.pid}'")
            @is_locked = true
          rescue Errno::EEXIST => e
            @logger.info("Failed to create the lock file `#{@file_path}' because it has been created by another process.")
            return false
          ensure
            f.close unless f.nil?
          end
          return true
        end

        if Time.new() - mtime > @expired
          @logger.debug("The lock `#{@file_path}' exists, but timeouts.")
          raise LockTimeoutError
        end

        @logger.debug("The lock `#{@file_path}' exists")
        false
      end

      def wait()
        loop do
          begin
            mtime = File.mtime(@file_path)
          rescue Errno::ENOENT => e
            @logger.debug("The lock `#{@file_path}' does not exist")
            return true
          end
          raise LockTimeoutError if Time.new() - mtime > @expired
          sleep(1) # second
        end
      end

      def unlock()
        File.delete(@file_path)
        @logger.debug("The lock `#{@file_path}' is deleted by the process `#{Process.pid}'")
        @is_locked = false
      rescue Errno::ENOENT => e
        raise LockNotFoundError
      end

      def update()
        raise LockNotOwnedError unless @is_locked
        begin
          File.open(@file_path, 'wb') { |f|
            f.write("#{Process.pid}")
          }
          @logger.debug("The lock `#{@file_path}' is updated by the process `#{Process.pid}'")
        rescue Errno::ENOENT => e
          raise LockNotFoundError
        end
      end
    end

    # Readers-Writer Lock
    #
    # Example codes:
    #
    # expired = 300 # seconds
    # lock = ReadersWriterLock.new("availability-set-${availability_set_name}", logger, expired)
    #
    # Readers operations:
    # lock.acquire_read_lock
    # begin
    #   data.retrieve
    # ensure
    #   lock.release_read_lock
    # end
    #
    # Writer operations:
    # if lock.acquire_write_lock
    #   begin
    #     data.modify!
    #   ensure
    #     lock.release_write_lock
    #   end
    # end
    #
    # The ReadersWriterLock is based on the design using two mutexes.
    # @See https://en.wikipedia.org/wiki/Readers%E2%80%93writer_lock#Using_two_mutexes
    #
    class ReadersWriterLock
      def initialize(lock_name, logger, expired = 300)
        @counter_file_path = "#{CPI_LOCK_DIR}/#{lock_name}-counter"
        @readers_mutex = FileMutex.new("#{lock_name}-readers", logger, expired)
        @writer_mutex = FileMutex.new("#{lock_name}-writer", logger, expired)
        @logger = logger
      end

      def acquire_read_lock
        is_locked = false
        loop do
          is_locked = @readers_mutex.lock
          break if is_locked
          @readers_mutex.wait
        end

        is_counter_increased = false
        counter = update_counter { |counter|
          @logger.debug("The counter `#{@counter_file_path}' is updated from `#{counter}' to `#{counter + 1}'")
          counter = counter + 1
        }
        is_counter_increased = true

        if counter == 1
          loop do
            break if @writer_mutex.lock
            @writer_mutex.wait
          end
        end
      rescue => e
        if is_counter_increased
          counter = update_counter { |counter|
            @logger.debug("The counter `#{@counter_file_path}' is updated from `#{counter}' to `#{counter - 1}'")
            counter = counter - 1
          }
        end
        raise e
      ensure
        @readers_mutex.unlock if is_locked
      end

      def release_read_lock
        is_locked = false
        loop do
          is_locked = @readers_mutex.lock
          break if is_locked
          @readers_mutex.wait
        end

        counter = update_counter { |counter|
          @logger.debug("The counter is `#{@counter_file_path}' updated from `#{counter}' to `#{counter - 1}'")
          counter = counter - 1
        }

        if counter == 0
          File.delete(@counter_file_path)
          @writer_mutex.unlock
        end
      ensure
        @readers_mutex.unlock if is_locked
      end

      def acquire_write_lock
        @writer_mutex.lock
      end

      def release_write_lock
        @writer_mutex.unlock
      end

      private

      def update_counter
        counter = 0
        if File.exists?(@counter_file_path)
          File.open(@counter_file_path, 'rb') { |f|
            counter = f.read().to_i
          }
        end
        File.open(@counter_file_path, 'wb') { |f|
          counter = yield counter
          f.write("#{counter}")
        }
        counter
      end
    end

    def mark_deleting_locks
      File.open(CPI_LOCK_DELETE, 'wb') { |f| f.write("Some errors happen. Will delete the locks when CPI starts next time.") }
    end

    def needs_deleting_locks?
      File.exists?(CPI_LOCK_DELETE)
    end

    def remove_deleting_mark
      File.delete(CPI_LOCK_DELETE)
    end

    def get_storage_account_type_by_instance_type(instance_type)
      instance_type = instance_type.downcase
      storage_account_type = STORAGE_ACCOUNT_TYPE_STANDARD_LRS
      if instance_type.start_with?("standard_ds") || instance_type.start_with?("standard_gs") || ((instance_type =~ /^standard_f(\d)+s/) == 0)
        storage_account_type = STORAGE_ACCOUNT_TYPE_PREMIUM_LRS
      end
      storage_account_type
    end

    def is_stemcell_storage_account?(tags)
      (STEMCELL_STORAGE_ACCOUNT_TAGS.to_a - tags.to_a).empty?
    end

    def is_ephemeral_disk?(name)
      name.end_with?(EPHEMERAL_DISK_POSTFIX)
    end

    def has_light_stemcell_property?(stemcell_properties)
      stemcell_properties.has_key?(LIGHT_STEMCELL_PROPERTY)
    end

    def is_light_stemcell_id?(stemcell_id)
      stemcell_id.start_with?(LIGHT_STEMCELL_PREFIX)
    end

    # use timestamp and process id to generate a unique string for computer name of Windows
    #
    def generate_windows_computer_name
      prefix = Time.now.to_f
      prefix = prefix.to_s.delete('.')
      prefix = prefix.to_i.to_s(32) # example timestamp 1482829740.3734238 -> 'd5e883lv66u'
      suffix = Process.pid.to_s(32) # default max pid 65536, .to_s(32) -> '2000'
      padding_length = WINDOWS_VM_NAME_LENGTH - prefix.length - suffix.length
      if padding_length >= 0
        prefix + '0'*padding_length + suffix
      else
        @logger.warn("Length of generated string is longer than expected, so it is truncated. It may be not unique.")
        (prefix + suffix)[prefix.length + suffix.length - WINDOWS_VM_NAME_LENGTH, prefix.length + suffix.length]  # get tail
      end
    end

    def validate_idle_timeout(idle_timeout_in_minutes)
      raise ArgumentError, 'idle_timeout_in_minutes needs to be an integer' unless idle_timeout_in_minutes.kind_of?(Integer)

      cloud_error('Minimum idle_timeout_in_minutes is 4 minutes') if idle_timeout_in_minutes < 4
      cloud_error('Maximum idle_timeout_in_minutes is 30 minutes') if idle_timeout_in_minutes > 30
    end
  end
end
