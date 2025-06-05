# frozen_string_literal: true

###############################################################################
# This client is for using Azure Resource Manager.
# The reasons why we do not use azure-sdk-for-ruby are as below:
#   1. azure-sdk-for-ruby is not always ready when new Azure features come
#   2. Various retries need to be handle
#   3. azure-sdk-for-ruby hides asynchronous calls from callers
###############################################################################
module Bosh::AzureCloud
  class AzureError < Bosh::Clouds::CloudError; end
  class AzureUnauthorizedError < AzureError; end
  class AzureNotFoundError < AzureError; end
  class AzureConflictError < AzureError; end
  class AzureInternalError < AzureError; end
  class AzureAsynInternalError < AzureError; end

  class AzureAsynchronousError < AzureError
    attr_accessor :status, :error

    def initialize(status = nil)
      @status = status
    end
  end

  class AzureClient
    include Helpers

    HTTP_CODE_OK                  = 200
    HTTP_CODE_CREATED             = 201
    HTTP_CODE_ACCEPTED            = 202
    HTTP_CODE_NO_CONTENT          = 204
    HTTP_CODE_BAD_REQUEST         = 400
    HTTP_CODE_UNAUTHORIZED        = 401
    HTTP_CODE_NOT_FOUND           = 404
    HTTP_CODE_REQUEST_TIMEOUT     = 408
    HTTP_CODE_CONFLICT            = 409
    HTTP_CODE_TOO_MANY_REQUESTS   = 429
    HTTP_CODE_INTERNAL_SERVER_ERROR           = 500
    HTTP_CODE_NOT_IMPLEMENTED                 = 501
    HTTP_CODE_BAD_GATEWAY                     = 502
    HTTP_CODE_SERVICE_UNAVAILABLE             = 503
    HTTP_CODE_GATEWAY_TIMEOUT                 = 504
    HTTP_CODE_HTTP_VERSION_NOT_SUPPORTED      = 505
    HTTP_CODE_VARIANT_ALSO_NEGOTIATES         = 506
    HTTP_CODE_INSUFFICIENT_STORAGE            = 507
    HTTP_CODE_LOOP_DETECTED                   = 508
    HTTP_CODE_NOT_EXTENDED                    = 510
    HTTP_CODE_NETWORK_AUTHENTICATION_REQUIRED = 511

    # https://docs.microsoft.com/en-us/azure/architecture/best-practices/retry-service-specific#general-rest-and-retry-guidelines
    AZURE_GENERAL_RETRYABLE_ERROR_CODES = [
      HTTP_CODE_REQUEST_TIMEOUT,
      HTTP_CODE_TOO_MANY_REQUESTS,
      HTTP_CODE_INTERNAL_SERVER_ERROR,
      HTTP_CODE_BAD_GATEWAY,
      HTTP_CODE_SERVICE_UNAVAILABLE,
      HTTP_CODE_GATEWAY_TIMEOUT
    ].freeze
    # https://docs.microsoft.com/en-us/azure/architecture/best-practices/retry-service-specific#azure-active-directory
    AZURE_AD_TOKEN_RETRYABLE_ERROR_CODES = AZURE_GENERAL_RETRYABLE_ERROR_CODES + [
      HTTP_CODE_NOT_IMPLEMENTED,
      HTTP_CODE_HTTP_VERSION_NOT_SUPPORTED,
      HTTP_CODE_VARIANT_ALSO_NEGOTIATES,
      HTTP_CODE_INSUFFICIENT_STORAGE,
      HTTP_CODE_LOOP_DETECTED,
      HTTP_CODE_NOT_EXTENDED,
      HTTP_CODE_NETWORK_AUTHENTICATION_REQUIRED
    ].freeze
    # https://docs.microsoft.com/en-us/azure/active-directory/managed-service-identity/how-to-use-vm-token#retry-guidance
    AZURE_MANAGED_IDENTITY_TOKEN_RETRYABLE_ERROR_CODES = AZURE_GENERAL_RETRYABLE_ERROR_CODES + [
      HTTP_CODE_NOT_FOUND,
      HTTP_CODE_NOT_IMPLEMENTED,
      HTTP_CODE_HTTP_VERSION_NOT_SUPPORTED,
      HTTP_CODE_VARIANT_ALSO_NEGOTIATES,
      HTTP_CODE_INSUFFICIENT_STORAGE,
      HTTP_CODE_LOOP_DETECTED,
      HTTP_CODE_NOT_EXTENDED,
      HTTP_CODE_NETWORK_AUTHENTICATION_REQUIRED
    ].freeze

    REST_API_PROVIDER_COMPUTE            = 'Microsoft.Compute'
    REST_API_VIRTUAL_MACHINES            = 'virtualMachines'
    REST_API_AVAILABILITY_SETS           = 'availabilitySets'
    REST_API_DISKS                       = 'disks'
    REST_API_DISK_ENCRYPTION_SETS        = 'diskEncryptionSets'
    REST_API_GALLERIES                   = 'galleries'
    REST_API_IMAGES                      = 'images'
    REST_API_SNAPSHOTS                   = 'snapshots'
    REST_API_VM_IMAGE                    = 'vmimage'
    REST_API_VM_SIZES                    = 'vmSizes'

    REST_API_PROVIDER_NETWORK            = 'Microsoft.Network'
    REST_API_PUBLIC_IP_ADDRESSES         = 'publicIPAddresses'
    REST_API_LOAD_BALANCERS              = 'loadBalancers'
    REST_API_NETWORK_INTERFACES          = 'networkInterfaces'
    REST_API_VIRTUAL_NETWORKS            = 'virtualNetworks'
    REST_API_NETWORK_SECURITY_GROUPS     = 'networkSecurityGroups'
    REST_API_APPLICATION_SECURITY_GROUPS = 'applicationSecurityGroups'
    REST_API_APPLICATION_GATEWAYS        = 'applicationGateways'

    REST_API_PROVIDER_STORAGE            = 'Microsoft.Storage'
    REST_API_STORAGE_ACCOUNTS            = 'storageAccounts'

    REST_API_PROVIDER_MANAGED_IDENTITY   = 'Microsoft.ManagedIdentity'
    REST_API_USER_ASSIGNED_IDENTITIES    = 'userAssignedIdentities'

    # Please add the key into this list if you want to redact its value in request body.
    CREDENTIAL_KEYWORD_LIST = %w[adminPassword client_secret customData].freeze

    CACHE_DIR = '/var/vcap/sys/run/azure_cpi'.freeze
    CACHE_SUBDIR = 'cache'.freeze
    CACHE_EXPIRY_SECONDS = 24 * 60 * 60 # 24 hours
    MAX_RESPONSE_BODY_LENGTH = 10000

    def initialize(azure_config, logger)
      @logger = logger

      @azure_config = azure_config
    end

    # Common
    def rest_api_url(resource_provider, resource_type, resource_group_name: nil, name: nil, others: nil)
      url = "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      resource_group_name = @azure_config.resource_group_name if resource_group_name.nil?
      url += "/resourceGroups/#{uri_escape(resource_group_name)}"
      url += "/providers/#{resource_provider}"
      url += "/#{resource_type}"
      url += "/#{uri_escape(name)}" unless name.nil?
      url += "/#{uri_escape(others)}" unless others.nil?
      url
    end

    # get single resource
    # example: /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/networkInterfaces/{networkInterfaceName}
    def get_resource_by_id(url, params = {})
      result = nil
      begin
        uri = http_url(url, params)
        response = http_get(uri)
        result = JSON.parse(response.body, symbolize_keys: false) unless response.body.nil? || response.body == ''
      rescue AzureNotFoundError => e
        @logger.debug("Resource not found for url #{url} with parms #{params}")
        result = nil
      end
      result
    end

    # get list of resources
    # example: /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/networkInterfaces
    def get_resources_by_url(url, params = {})
      result = nil
      next_url = nil
      begin
        uri = http_url(url, params)
        response = http_get(uri)
        unless response.body.nil?
          body = JSON.parse(response.body, symbolize_keys: false)
          result = body
          next_url = body['nextLink']
        end

        until next_url.nil?
          @logger.debug("Getting resources from nextLink #{next_url}")
          uri = URI(next_url)
          response = http_get(uri)
          cloud_error("Got empty page from nextLink #{next_url}") if response.body.nil?

          body = JSON.parse(response.body, symbolize_keys: false)
          result.deep_merge!(body)
          next_url = body['nextLink']
        end
      rescue AzureNotFoundError => e
        @logger.debug("Resources not found for url #{url} with parms #{params}")
        result = nil
      end
      result
    end

    # Resource Groups

    # Create resource group
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] location             - location of the resource group.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups#ResourceGroups_CreateOrUpdate
    #
    def create_resource_group(resource_group_name, location)
      url =  "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      url += "/resourceGroups/#{uri_escape(resource_group_name)}"

      resource_group = {
        'name' => resource_group_name,
        'location' => location
      }

      http_put(url, resource_group)
    end

    # Get resource group's information
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups#ResourceGroups_Get
    #
    def get_resource_group(resource_group_name)
      resource_group = nil

      url =  "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      url += "/resourceGroups/#{uri_escape(resource_group_name)}"
      result = get_resource_by_id(url)

      unless result.nil?
        resource_group = {}
        resource_group[:id]                 = result['id']
        resource_group[:name]               = result['name']
        resource_group[:location]           = result['location']
        resource_group[:tags]               = result['tags']
        resource_group[:provisioning_state] = result['properties']['provisioningState']
      end
      resource_group
    end

    # Compute/Virtual Machines

    # Provisions a virtual machine based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash]   vm_params            - Parameters for creating the virtual machine.
    # @param [Array]  network_interfaces   - Network Interface Instances. network_interfaces[0] will be picked as the primary network and bound to public ip or load balancers.
    # @param [Hash]   availability_set     - Availability set.
    #
    # ==== vm_params
    #
    # Accepted key/value pairs are:
    # * +:name+                 - String. Name of virtual machine.
    # * +:computer_name+        - String. Specifies the host OS name of the virtual machine. Above name will be used if this is not set.
    #                             Max-length (Windows): 15 characters
    #                             Max-length (Linux): 64 characters.
    # * +:location+             - String. The location where the virtual machine will be created.
    # * +:tags+                 - Hash. Tags of virtual machine.
    # * +:vm_size+              - String. Specifies the size of the virtual machine instance.
    # * +:custom_data+          - String. Specifies a base-64 encoded string of custom data.
    # * +:os_type+              - String. OS type of virutal machine. Possible values: linux, windows. When os_type is windows, the VM must be a managed disk VM.
    # * +:image_reference+      - Hash. Reference a platform image. When this is set, neither image_id nor image_uri is needed.
    #
    #   When os_type is linux, below parameters are required
    # * +:ssh_username+         - String. User name for the virtual machine instance.
    # * +:ssh_cert_data+        - String. The content of SSH certificate.
    #
    #   When os_type is windows, below parameters are required
    # * +:windows_username+     - String. User name for the virtual machine instance.
    # * +:windows_password+     - String. Password for the virtual machine instance.
    #
    # * +:managed+              - Boolean. Needs to be true to create managed disk VMs. Default value is nil.
    #
    #   When managed is true, below parameters are required
    # * +:image_id+                   - String. The id of the image to create the virtual machine.
    # * +:os_disk+                    - Hash. OS Disk for the virtual machine instance.
    # *   +:disk_name+                - String. The name of the OS disk.
    # *   +:disk_caching+             - String. The caching option of the OS disk. Possible values: None, ReadOnly or ReadWrite.
    # *   +:disk_size+                - Integer. The size in GiB of the OS disk. It could be nil.
    # *   +:disk_encryption_set_name+ - String. If specified, encrypted the os_disk with the customer provided encryption key used in the provided disk encryption set.
    # * +:ephemeral_disk+             - Hash. Ephemeral Disk for the virtual machine instance. It could be nil.
    # *   +:disk_name+                - String. The name of the ephemeral disk.
    # *   +:disk_caching+             - String. The caching option of the ephemeral disk. Possible values: None, ReadOnly or ReadWrite.
    # *   +:disk_size+                - Integer. The size in GiB of the ephemeral disk.
    # *   +:disk_type+                - String. The disk type of the ephemeral disk.
    # *   +:disk_encryption_set_name+ - String. If specified, encrypted the ephemeral_disk with the customer provided encryption key used in the provided disk encryption set.
    #
    #   When managed is true and root_disk type is not 'remote' below parameters are required
    # * +:image_id+             - String. The id of the image to create the virtual machine.
    # * +:ephemeral_os_disk+    - Hash. Azure Ephemeral OS Disk for the virtual machine instance.
    # *   +:disk_name+          - String. The name of the ephemeral disk.
    # *   +:disk_size+          - Integer. The size in GiB of the OS disk. It could be nil.
    # *   +:disk_placement+     - String. Where Ephemeral OS Disk is placed. Possible values: remote, resource-disk, cache-disk.
    #
    #   When managed is false or nil, below parameters are required
    # * +:image_uri+            - String. The URI of the image.
    # * +:os_disk+              - Hash. OS Disk for the virtual machine instance.
    # *   +:disk_name+          - String. The name of the OS disk.
    # *   +:disk_uri+           - String. The URI of the OS disk.
    # *   +:disk_caching+       - String. The caching option of the OS disk. Possible values: None, ReadOnly or ReadWrite.
    # *   +:disk_size+          - Integer. The size in GiB of the OS disk. It could be nil.
    # * +:ephemeral_disk+       - Hash. Ephemeral Disk for the virtual machine instance. It could be nil.
    # *   +:disk_name+          - String. The name of the ephemeral disk.
    # *   +:disk_uri+           - String. The URI of the ephemeral disk.
    # *   +:disk_caching+       - String. The caching option of the ephemeral disk. Possible values: None, ReadOnly or ReadWrite.
    # *   +:disk_size+          - Integer. The size in GiB of the ephemeral disk.
    #
    #   When debug_mode is on, CPI will use below parameter for boot diagnostics
    # * +:diag_storage_uri      - String. Diagnostics storage account URI.
    #
    #  When virtual machine is in an availability zone
    # * +:zone+                 - String. Zone number in string. Possible values: "1", "2" or "3".
    #
    #  When virtual machine is associated to an identity
    # * +:identity+             - Hash. The identity associated with the VM.
    # *   +:type+               - String. The identity type used for the VM. Possible values: "SystemAssigned" and "UserAssigned".
    # *   +:identity_name+      - String. The user identity associated with the VM.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
    #
    def create_virtual_machine(resource_group_name, vm_params, network_interfaces, availability_set = nil)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: vm_params[:name])

      os_profile = _build_os_profile(vm_params)

      network_interfaces_params = []
      network_interfaces.each_with_index do |network_interface, index|
        network_interfaces_params.push(
          'id' => network_interface[:id],
          'properties' => {
            # NOTE: The first NIC is the Primary/Gateway network. See: `Bosh::AzureCloud::NetworkConfigurator.initialize`.
            'primary' => index.zero?
          }
        )
      end

      vm = {
        'name' => vm_params[:name],
        'location' => vm_params[:location],
        'type' => "#{REST_API_PROVIDER_COMPUTE}/#{REST_API_VIRTUAL_MACHINES}",
        'tags' => vm_params[:tags],
        'properties' => {
          'hardwareProfile' => {
            'vmSize' => vm_params[:vm_size]
          },
          'osProfile' => os_profile,
          'networkProfile' => {
            'networkInterfaces' => network_interfaces_params
          }
        }
      }

      unless vm_params[:capacity_reservation_group].nil?
        vm['properties']['capacityReservation'] = {
          'capacityReservationGroup' => {
            'id' => rest_api_url(REST_API_PROVIDER_COMPUTE, 'capacityReservationGroups', resource_group_name: resource_group_name, name: vm_params[:capacity_reservation_group])
          }
        }
      end

      unless vm_params[:identity].nil?
        identity_type = vm_params[:identity][:type]
        if identity_type == MANAGED_IDENTITY_TYPE_USER_ASSIGNED
          identity_id = rest_api_url(REST_API_PROVIDER_MANAGED_IDENTITY, REST_API_USER_ASSIGNED_IDENTITIES, resource_group_name: resource_group_name, name: vm_params[:identity][:identity_name])
          vm['identity'] = {
            'type' => MANAGED_IDENTITY_TYPE_USER_ASSIGNED,
            'userAssignedIdentities' => { identity_id => {} }
          }
        else
          vm['identity'] = {
            'type' => MANAGED_IDENTITY_TYPE_SYSTEM_ASSIGNED
          }
        end
      end

      vm['zones'] = [vm_params[:zone]] unless vm_params[:zone].nil?

      os_disk = {}
      unless vm_params[:os_disk].nil?
        os_disk = {
          'name' => vm_params[:os_disk][:disk_name],
          'createOption' => 'FromImage',
          'caching' => vm_params[:os_disk][:disk_caching]
        }
        os_disk['diskSizeGB'] = vm_params[:os_disk][:disk_size] unless vm_params[:os_disk][:disk_size].nil?
        if vm_params[:os_disk][:disk_encryption_set_name]
          disk_encryption_set_id = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISK_ENCRYPTION_SETS, name: vm_params[:os_disk][:disk_encryption_set_name])
          os_disk['managedDisk'] = { 'diskEncryptionSet' => { 'id' => disk_encryption_set_id } }
        end
      end

      unless vm_params[:ephemeral_os_disk].nil?
        os_disk = {
          'diffDiskSettings' => {
            'option' => 'Local',
            'placement' => vm_params[:ephemeral_os_disk][:disk_placement]
          },
          'caching' => vm_params[:ephemeral_os_disk][:disk_caching],
          'createOption' => 'FromImage',
          'name' => vm_params[:ephemeral_os_disk][:disk_name]
        }
        os_disk['diskSizeGB'] = vm_params[:ephemeral_os_disk][:disk_size] unless vm_params[:ephemeral_os_disk][:disk_size].nil?
        if vm_params[:ephemeral_os_disk][:disk_encryption_set_name]
          disk_encryption_set_id = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISK_ENCRYPTION_SETS, name: vm_params[:ephemeral_os_disk][:disk_encryption_set_name])
          os_disk['managedDisk'] = { 'diskEncryptionSet' => { 'id' => disk_encryption_set_id } }
        end
      end

      if vm_params[:image_reference].nil?
        if vm_params[:managed]
          vm['properties']['storageProfile'] = {
            'imageReference' => {
              'id' => vm_params[:image_id]
            },
            'osDisk' => os_disk
          }
        else
          os_disk.merge!(
            'osType' => vm_params[:os_type],
            'image' => {
              'uri' => vm_params[:image_uri]
            },
            'vhd' => {
              'uri' => vm_params[:os_disk][:disk_uri]
            }
          )
          vm['properties']['storageProfile'] = {
            'osDisk' => os_disk
          }
        end
      else
        unless vm_params[:managed]
          os_disk['osType'] = vm_params[:os_type]
          os_disk['vhd'] = {
            'uri' => vm_params[:os_disk][:disk_uri]
          }
        end

        vm['properties']['storageProfile'] = {
          'imageReference' => vm_params[:image_reference],
          'osDisk' => os_disk
        }

        vm['plan'] = {
          'name' => vm_params[:image_reference]['sku'],
          'publisher' => vm_params[:image_reference]['publisher'],
          'product' => vm_params[:image_reference]['offer']
        }
      end

      unless vm_params[:ephemeral_disk].nil?
        vm['properties']['storageProfile']['dataDisks'] = [{
          'name' => vm_params[:ephemeral_disk][:disk_name],
          'lun' => 0,
          'createOption' => 'Empty',
          'diskSizeGB' => vm_params[:ephemeral_disk][:disk_size],
          'caching' => vm_params[:ephemeral_disk][:disk_caching]
        }]
        if vm_params[:managed]
          managed_disk = vm['properties']['storageProfile']['dataDisks'][0]['managedDisk'] = {}
          if vm_params[:ephemeral_disk][:disk_type]
            managed_disk['storageAccountType'] = vm_params[:ephemeral_disk][:disk_type]
          end
          if vm_params[:ephemeral_disk][:disk_encryption_set_name]
            disk_encryption_set_id = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISK_ENCRYPTION_SETS, name: vm_params[:ephemeral_disk][:disk_encryption_set_name])
            managed_disk['diskEncryptionSet'] = {'id' => disk_encryption_set_id}
          end
        else
          vm['properties']['storageProfile']['dataDisks'][0]['vhd'] = {
            'uri' => vm_params[:ephemeral_disk][:disk_uri]
          }
        end
      end

      unless availability_set.nil?
        vm['properties']['availabilitySet'] = {
          'id' => availability_set[:id]
        }
      end

      unless vm_params[:diag_storage_uri].nil?
        vm['properties']['diagnosticsProfile'] = {
          'bootDiagnostics' => {
            'enabled' => true,
            'storageUri' => vm_params[:diag_storage_uri]
          }
        }
      end

      params = {
        'validating' => 'true'
      }

      response = http_put(url, vm, params)
      result = JSON.parse(response.body, symbolize_keys: false) unless response.body.nil? || response.body == ''

      _parse_virtual_machine(result, false)
    end

    # List the available virtual machine sizes by location
    # @param [String] location - Location of virtual machine.
    #
    # @return [Array]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinesizes/list
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def list_available_virtual_machine_sizes_by_location(location)
      vm_sizes = []
      url =  "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      url += "/providers/#{REST_API_PROVIDER_COMPUTE}"
      url += "/locations/#{location}"
      url += "/#{REST_API_VM_SIZES}"
      result = get_resource_by_id(url)

      unless result.nil? || result['value'].nil?
        result['value'].each do |value|
          vm_sizes << parse_vm_size(value)
        end
      end
      vm_sizes
    end

    # List the available virtual machine sizes by availability set
    # @param [String] availability_set_name - Name of availability set.
    #
    # @return [Array]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/availabilitysets/listavailablesizes
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def list_available_virtual_machine_sizes_by_availability_set(resource_group_name, availability_set_name)
      vm_sizes = []
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_AVAILABILITY_SETS, resource_group_name: resource_group_name, name: availability_set_name, others: REST_API_VM_SIZES)
      result = get_resource_by_id(url)

      unless result.nil? || result['value'].nil?
        result['value'].each do |value|
          vm_sizes << parse_vm_size(value)
        end
      end
      vm_sizes
    end

    # Restart a virtual machine
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of virtual machine.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-restart
    #
    def restart_virtual_machine(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: name, others: 'restart')
      http_post(url)
    end

    # Set tags for a virtual machine
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of virtual machine.
    # @param [Hash]   tags                 - tags key/value pairs.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
    #
    def update_tags_of_virtual_machine(resource_group_name, name, tags)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: name)
      vm = get_resource_by_id(url)
      raise AzureNotFoundError, "update_tags_of_virtual_machine - cannot find the virtual machine by name '#{name}' in resource group '#{resource_group_name}'" if vm.nil?

      vm = remove_resources_from_vm(vm)
      vm['tags'].merge!(tags)
      http_put(url, vm)
    end

    # Attach a specified disk to a virtual machine
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vm_name              - Name of virtual machine.
    # @param [Hash]   disk_params          - Parameters of disk.
    #
    # ==== disk_params
    #
    # Accepted key/value pairs are:
    # * +:disk_name+              - String.  Disk name.
    # * +:caching+                - String.  Caching option: None, ReadOnly or ReadWrite.
    # * +:managed+                - Boolean. Needs to be true to attach disk to a managed disk VM.
    # * +:disk_bosh_id            - String.  Disk id for BOSH
    #
    #   When managed is true, below parameters are required
    # * +:disk_id+                - String.  ID of a managed disk.
    #
    #   When managed is false or nil, below parameters are required
    # * +:disk_uri+               - String.  URI of an unmanaged disk.
    # * +:disk_size+              - Integer. Size of disk. Needs to be specified when attaching an unmanaged disk.
    #
    # @return [Integer]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
    #
    def attach_disk_to_virtual_machine(resource_group_name, vm_name, disk_params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: vm_name)
      vm = get_resource_by_id(url)
      raise AzureNotFoundError, "attach_disk_to_virtual_machine - cannot find the virtual machine by name '#{vm_name}' in resource group '#{resource_group_name}'" if vm.nil?

      # Record disk_id in VM's tag, which will be used in cpi.get_disks(instance_id)
      disk_id_tag = {
        "#{DISK_ID_TAG_PREFIX}-#{disk_params[:disk_name]}" => disk_params[:disk_bosh_id]
      }
      vm['tags'].merge!(disk_id_tag)

      vm = remove_resources_from_vm(vm)

      disk_info = DiskInfo.for(vm['properties']['hardwareProfile']['vmSize'])
      lun = nil
      data_disks = vm['properties']['storageProfile']['dataDisks']
      (0..(disk_info.count - 1)).each do |i|
        disk = data_disks.find { |disk| disk['lun'] == i }
        if disk.nil?
          lun = i
          break
        end
      end

      disk_name = disk_params[:disk_name]
      caching = disk_params[:caching]
      managed = disk_params[:managed]
      disk_id = disk_params[:disk_id]
      disk_uri = disk_params[:disk_uri]
      disk_size = disk_params[:disk_size]

      raise AzureError, "attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine '#{vm_name}' for the new disk '#{disk_name}'" if lun.nil?

      new_disk = {
        'name' => disk_name,
        'lun' => lun,
        'createOption' => 'Attach',
        'caching' => caching
      }
      if managed
        new_disk['managedDisk'] = { 'id' => disk_id }
      else
        new_disk['vhd'] = { 'uri' => disk_uri }
        new_disk['diskSizeGb'] = disk_size
      end

      vm['properties']['storageProfile']['dataDisks'].push(new_disk)
      @logger.info("attach_disk_to_virtual_machine - attach disk '#{disk_name}' to lun '#{lun}' of the virtual machine '#{vm_name}', managed: '#{managed}'")
      http_put(url, vm)

      lun
    end

    # Detach a specified disk from a virtual machine
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of virtual machine.
    # @param [String] disk_name            - Disk name.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
    #
    def detach_disk_from_virtual_machine(resource_group_name, name, disk_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: name)
      vm = get_resource_by_id(url)
      raise AzureNotFoundError, "detach_disk_from_virtual_machine - cannot find the virtual machine by name '#{name}' in resource group '#{resource_group_name}'" if vm.nil?

      disk_id_tag = "#{DISK_ID_TAG_PREFIX}-#{disk_name}"
      vm['tags'].delete(disk_id_tag)

      vm = remove_resources_from_vm(vm)

      @logger.debug("detach_disk_from_virtual_machine - virtual machine:\n#{JSON.pretty_generate(vm)}")
      disk = vm['properties']['storageProfile']['dataDisks'].find { |disk| disk['name'] == disk_name }
      if disk.nil?
        raise Bosh::Clouds::DiskNotAttached.new(true),
              "The disk #{disk_name} is not attached to the virtual machine #{name}"
      end

      vm['properties']['storageProfile']['dataDisks'].delete_if { |disk| disk['name'] == disk_name }

      @logger.info("detach_disk_from_virtual_machine - detach disk #{disk_name} from lun #{disk['lun']}")
      http_put(url, vm)
    end

    # Get a virtual machine's information
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of virtual machine.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-get
    #
    def get_virtual_machine_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: name)
      get_virtual_machine(url)
    end

    # Get a virtual machine's information
    # @param [String] url - URL of virtual machine.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-get
    #
    def get_virtual_machine(url)
      vm = nil
      result = get_resource_by_id(url)

      _parse_virtual_machine(result, true)
    end

    # Parse the Azure response to get a virtual machine's information
    # @param [Hash] raw_virtual_machine - VM response from Azure - parsed as JSON
    #
    # @return [Hash]
    def _parse_virtual_machine(raw_virtual_machine, extend_resources)
      vm = nil

      unless raw_virtual_machine.nil?
        vm = {}
        vm[:id]       = raw_virtual_machine['id']
        vm[:name]     = raw_virtual_machine['name']
        vm[:location] = raw_virtual_machine['location']
        vm[:tags]     = raw_virtual_machine['tags']

        if raw_virtual_machine.key?('identity')
          vm[:identity] = {}
          vm[:identity][:type] = raw_virtual_machine['identity']['type']
          vm[:identity][:user_assigned_identities] = raw_virtual_machine['identity']['userAssignedIdentities']
        end

        vm[:zone]  = raw_virtual_machine['zones'][0] unless raw_virtual_machine['zones'].nil?

        properties = raw_virtual_machine['properties']
        vm[:provisioning_state] = properties['provisioningState']
        vm[:vm_size]            = properties['hardwareProfile']['vmSize']

        if extend_resources
          vm[:availability_set] = get_availability_set(properties['availabilitySet']['id']) unless properties['availabilitySet'].nil?
        else
          vm[:availability_set] = {}
          vm[:availability_set][:id] = properties['availabilitySet']['id'] unless properties['availabilitySet'].nil?
        end

        storage_profile = properties['storageProfile']
        os_disk = storage_profile['osDisk']
        vm[:os_disk] = {}
        vm[:os_disk][:name]    = os_disk['name']
        vm[:os_disk][:caching] = os_disk['caching']
        vm[:os_disk][:size]    = os_disk['diskSizeGb']

        vm[:os_disk][:uri]     = os_disk['vhd']['uri'] if os_disk.key?('vhd')
        if os_disk.key?('managedDisk')
          vm[:os_disk][:managed_disk] = {}
          vm[:os_disk][:managed_disk][:id]                   = os_disk['managedDisk']['id']
          vm[:os_disk][:managed_disk][:storage_account_type] = os_disk['managedDisk']['storageAccountType']
        end

        vm[:data_disks] = []
        storage_profile['dataDisks'].each do |data_disk|
          disk = {}
          disk[:name]    = data_disk['name']
          disk[:lun]     = data_disk['lun']
          disk[:caching] = data_disk['caching']
          disk[:size]    = data_disk['diskSizeGb']

          disk[:uri]     = data_disk['vhd']['uri'] if data_disk.key?('vhd')
          if data_disk.key?('managedDisk')
            disk[:managed_disk] = {}
            disk[:managed_disk][:id]                   = data_disk['managedDisk']['id']
            disk[:managed_disk][:storage_account_type] = data_disk['managedDisk']['storageAccountType']
          end

          disk[:disk_bosh_id] = raw_virtual_machine['tags'].fetch("#{DISK_ID_TAG_PREFIX}-#{data_disk['name']}", data_disk['name'])

          vm[:data_disks].push(disk)
        end

        vm[:network_interfaces] = []
        properties['networkProfile']['networkInterfaces'].each do |nic_properties|
          if extend_resources
            vm[:network_interfaces].push(get_network_interface(nic_properties['id']))
          else
            interface = {}
            interface[:id] = nic_properties['id']
            vm[:network_interfaces].push(interface)
          end
        end

        boot_diagnostics = properties.fetch('diagnosticsProfile', {}).fetch('bootDiagnostics', {})
        vm[:diag_storage_uri] = boot_diagnostics['storageUri'] if boot_diagnostics['enabled']
      end

      vm
    end

    # Delete a virtual machine
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of virtual machine.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-delete
    #
    def delete_virtual_machine(resource_group_name, name)
      @logger.debug("delete_virtual_machine - trying to delete '#{name}' from resource group '#{resource_group_name}'")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINES, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Compute/Availability Sets

    # Create an availability set based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name       - Name of resource group.
    # @param [Hash] params                      - Parameters for creating the availability set.
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of availability set.
    # * +:location+                     - String. The location where the availability set will be created.
    # * +:tags+                         - Hash. Tags of availability set.
    # * +:platform_update_domain_count+ - Integer. Specifies the update domain count of availability set.
    # * +:platform_fault_domain_count+  - Integer. Specifies the fault domain count of availability set. The max value is 2 if managed is true.
    # * +:managed                       - Boolean. Needs to be true if the availability set intends to host managed disk VMs.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/availabilitysets/availabilitysets-create
    #
    def create_availability_set(resource_group_name, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_AVAILABILITY_SETS, resource_group_name: resource_group_name, name: params[:name])
      availability_set = {
        'name' => params[:name],
        'type' => "#{REST_API_PROVIDER_COMPUTE}/#{REST_API_AVAILABILITY_SETS}",
        'location' => params[:location],
        'tags' => params[:tags],
        'properties' => {
          'platformUpdateDomainCount' => params[:platform_update_domain_count],
          'platformFaultDomainCount' => params[:platform_fault_domain_count]
        }
      }

      if params[:managed]
        availability_set['sku'] = {
          'name' => 'Aligned'
        }
      end

      http_put(url, availability_set)
    end

    # Get an availability set's information
    # @param [String] resource_group_name       - Name of resource group.
    # @param [String] name                      - Name of availability set.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/availabilitysets/availabilitysets-get
    #
    def get_availability_set_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_AVAILABILITY_SETS, resource_group_name: resource_group_name, name: name)
      get_availability_set(url)
    end

    # Get an availability set's information
    # @param [String] url - URL of availability set.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/availabilitysets/availabilitysets-get
    #
    def get_availability_set(url)
      availability_set = nil
      result = get_resource_by_id(url)
      unless result.nil?
        availability_set = {}
        availability_set[:id]       = result['id']
        availability_set[:name]     = result['name']
        availability_set[:location] = result['location']
        availability_set[:tags]     = result['tags']

        availability_set[:managed] = false
        availability_set[:managed] = true if !result['sku'].nil? && (result['sku']['name'] == 'Aligned')

        properties = result['properties']
        availability_set[:provisioning_state]           = properties['provisioningState']
        availability_set[:platform_update_domain_count] = properties['platformUpdateDomainCount']
        availability_set[:platform_fault_domain_count]  = properties['platformFaultDomainCount']
        availability_set[:virtual_machines]             = []
        properties['virtualMachines']&.each do |vm|
          availability_set[:virtual_machines].push(id: vm['id'])
        end
      end
      availability_set
    end

    # Delete an availability set
    # @param [String] resource_group_name       - Name of resource group.
    # @param [String] name                      - Name of availability set.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/availabilitysets/availabilitysets-delete
    #
    def delete_availability_set(resource_group_name, name)
      @logger.debug("delete_availability_set - trying to delete '#{name}' from resource group '#{resource_group_name}'")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_AVAILABILITY_SETS, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Compute/Disks

    # Create an empty managed disk based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash]   params               - Parameters for creating the empty managed disk.
    #
    # ==== params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of the empty managed disk.
    # * +:location+                     - String. The location where the empty managed disk will be created.
    # * +:tags+                         - Hash. Tags of the empty managed disk.
    # * +:disk_size+                    - Integer. Specifies the size in GB of the empty managed disk.
    # * +:account_type+                 - String. Specifies the account type of the empty managed disk.
    #                                     Optional values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
    # * +:disk_encryption_set_name+     - String. If specified, encrypted the disk with the customer provided encryption key used in the provided disk encryption set.
    # When disk is in a zone
    # * +:zone+                         - String. Zone number in string.
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/examples/CreateAnEmptyManagedDisk.json
    #
    def create_empty_managed_disk(resource_group_name, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: params[:name])
      disk = {
        'location' => params[:location],
        'tags' => params[:tags],
        'sku' => {
          'name' => params[:account_type]
        },
        'properties' => {
          'creationData' => {
            'createOption' => 'Empty'
          },
          'diskSizeGB' => params[:disk_size]
        }
      }
      disk['zones'] = [params[:zone]] unless params[:zone].nil?
      disk['properties']['diskIOPSReadWrite'] = params[:iops] unless params[:iops].nil?
      disk['properties']['diskMBpsReadWrite'] = params[:mbps] unless params[:mbps].nil?
      if params[:disk_encryption_set_name]
        disk_encryption_set_id = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISK_ENCRYPTION_SETS, name: params[:disk_encryption_set_name])
        disk['properties']['encryption'] = {
          'diskEncryptionSetId' => disk_encryption_set_id,
          'type' => 'EncryptionAtRestWithCustomerKey'
        }
      end
      http_put(url, disk)
    end

    # Update a managed disk based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of the disk that should be updated.
    # @param [Hash]   params               - Parameters for creating the empty managed disk.
    #
    # ==== params
    #
    # Accepted key/value pairs are:
    # * +:location+                     - String. The new location of the disk.
    # * +:tags+                         - Hash. The new tags of the disk.
    # * +:account_type+                 - String. Specifies the new account type for the disk.
    #                                     Allowed values: Standard_LRS, StandardSSD_LRS, Premium_LRS, PremiumV2_LRS,
    #                                     UltraSSD_LRS.
    # * +:disk_size+                    - Integer. Specifies the new size in GB of the disk.
    # * +:zone+                         - String. The new zone of the disk.
    #                                     Allowed values: 1, 2, 3
    # * +:iops+                         - Integer. Specifies the new IOPS allowed for this disk.
    # * +:mbps+                         - Integer. Specifies the new MBps allowed for this disk.
    #
    # @See https://learn.microsoft.com/en-us/rest/api/compute/disks/update?view=rest-compute-2023-04-02&tabs=HTTP
    def update_managed_disk(resource_group_name, name, params)
      raise AzureNotFoundError, "Disk parameter 'name' must not be empty" if name.empty?

      request_body = { 'properties' => {} }
      request_body['location'] = params[:location] if params[:location]
      request_body['tags'] = params[:tags] if params[:tags]
      request_body['sku'] = { 'name' => params[:account_type] } if params[:account_type]
      request_body['properties']['diskSizeGB'] = params[:disk_size] if params[:disk_size]
      request_body['properties']['diskIOPSReadWrite'] = params[:iops] if params[:iops]
      request_body['properties']['diskMBpsReadWrite'] = params[:mbps] if params[:mbps]
      request_body.delete('properties') if request_body['properties'].empty?
      return unless request_body.any?

      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: name)
      http_patch(url, request_body)
    end

    def resize_managed_disk(resource_group_name, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: params[:name])
      disk = {
        'properties' => {
          'diskSizeGB' => params[:disk_size]
        }
      }
      http_patch(url, disk)
    end

    def update_managed_disk_performance(resource_group_name, name, iops, mbps)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: name)
      disk = {
        'properties' => {
        }
      }

      disk['properties']['diskIOPSReadWrite'] = iops unless iops.nil?
      disk['properties']['diskMBpsReadWrite'] = mbps unless mbps.nil?

      http_patch(url, disk)
    end

    # Create a managed disk from storage blob SAS URI (import).
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash] params                 - Parameters for creating the managed disk.
    #
    # ==== params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of the managed disk.
    # * +:location+                     - String. The location where the managed disk will be created.
    # * +:tags+                         - Hash. Tags of the managed disk.
    # * +:source_uri+                   - String. The SAS URI of the source storage blob.
    # * +:account_type+                 - String. Specifies the account type of the managed disk.
    #                                     Optional values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
    # When disk is in a zone
    # * +:zone+                         - String. Zone number in string.
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/examples/CreateAManagedDiskByImportingAnUnmanagedBlobFromTheSameSubscription.json
    #
    def create_managed_disk_from_blob(resource_group_name, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: params[:name])
      disk = {
        'location' => params[:location],
        'tags' => params[:tags],
        'sku' => {
          'name' => params[:account_type]
        },
        'properties' => {
          'creationData' => {
            'createOption' => 'Import',
            'sourceUri' => params[:source_uri],
            'storageAccountId' => params[:storage_account_id]
          }
        }
      }
      disk['zones'] = [params[:zone]] unless params[:zone].nil?
      http_put(url, disk)
    end

    # Create a managed disk by copying a snapshot
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash] disk_params            - Parameters for creating the managed disk.
    # @param [Hash] snapshot_name          - snapshot name
    #
    # ==== params
    #
    # Accepted key/value pairs for disk_params are:
    # * +:name+                         - String. Name of the managed disk.
    # * +:location+                     - String. The location where the managed disk will be created.
    # * +:tags+                         - Hash. Tags of the managed disk.
    # * +:account_type+                 - String. Specifies the account type of the managed disk.
    #                                     Optional values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
    # When disk is in a zone
    # * +:zone+                         - String. Zone number in string.
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/examples/CreateAManagedDiskByCopyingASnapshot.json
    #
    def create_managed_disk_from_snapshot(resource_group_name, disk_params, snapshot_name)
      disk_url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: disk_params[:name])
      snapshot_url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_SNAPSHOTS, resource_group_name: resource_group_name, name: snapshot_name)
      disk = {
        'location' => disk_params[:location],
        'sku' => {
          'name' => disk_params[:account_type]
        },
        'properties' => {
          'creationData' => {
            'createOption' => 'Copy',
            'sourceResourceId' => snapshot_url
          }
        }
      }
      disk['zones'] = [disk_params[:zone]] unless disk_params[:zone].nil?
      disk['tags']  = disk_params[:tags] unless disk_params[:tags].nil?
      http_put(disk_url, disk)
    end

    # Delete a managed disk
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of managed disk.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    def delete_managed_disk(resource_group_name, name)
      @logger.debug("delete_managed_disk - trying to delete #{name} from resource group #{resource_group_name}")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Get a managed disk's information
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of managed disk.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    def get_managed_disk_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: name)
      get_managed_disk(url)
    end

    # Get a managed disk's information
    # @param [String] url - URL of managed disk.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    def get_managed_disk(url)
      result = get_resource_by_id(url)
      parse_managed_disk(result)
    end

    # Compute/Images

    # Create a vm image
    #
    # ==== Attributes
    #
    # @param [Hash] params   - Parameters for creating the user image.
    #
    # ==== params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of the user image.
    # * +:location+                     - String. The location where the user image will be created.
    # * +:tags+                         - Hash. Tags of the user image.
    # * +:os_type+                      - String. OS type. Possible values: linux.
    # * +:source_uri+                   - String. The SAS URI of the source storage blob.
    # * +:account_type+                 - String. Specifies the account type of the user image.
    #                                     Possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #      https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/examples/CreateAnImageFromABlob.json
    #
    def create_user_image(params)
      @logger.debug("create_user_image - trying to create a user image '#{params[:name]}'")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_IMAGES, name: params[:name])
      user_image = {
        'location' => params[:location],
        'tags' => params[:tags],
        'properties' => {
          'storageProfile' => {
            'osDisk' => {
              'osType' => params[:os_type],
              'osState' => 'generalized',
              'blobUri' => params[:source_uri],
              'caching' => 'readwrite',
              'storageAccountType' => params[:account_type]
            }
          },
          'hyperVGeneration' => 'V1'
        }
      }

      http_put(url, user_image)
    end

    # Delete a user image
    # @param [String] name - Name of user image.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def delete_user_image(name)
      @logger.debug("delete_user_image - trying to delete '#{name}'")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_IMAGES, name: name)
      http_delete(url)
    end

    # Get a user image's information
    # @param [String] name - Name of user image
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def get_user_image_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_IMAGES, name: name)
      get_user_image(url)
    end

    # Get a user image's information
    # @param [String] url - URL of user image.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def get_user_image(url)
      result = get_resource_by_id(url)
      parse_user_image(result)
    end

    # List user images within the default resource group
    #
    # @return [Array]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def list_user_images
      user_images = []
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_IMAGES)
      result = get_resource_by_id(url)
      unless result.nil?
        result['value'].each do |value|
          user_image = parse_user_image(value)
          user_images << user_image
        end
      end
      user_images
    end

    # Compute/Snapshots
    # Create a snapshot for a managed disk
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash] params                 - Parameters for creating the managed snapshot.
    #
    # ==== params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of the snapshot.
    # * +:tags+                         - Hash. Tags of the snapshot.
    # * +:disk_name+                    - String. Name of the disk.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    def create_managed_snapshot(resource_group_name, params)
      snapshot_name = params[:name]
      disk_name = params[:disk_name]
      @logger.debug("create_managed_snapshot - trying to create a snapshot '#{snapshot_name}' for the managed disk '#{disk_name}'")
      disk = get_managed_disk_by_name(resource_group_name, disk_name)
      raise AzureNotFoundError, "The disk '#{disk_name}' cannot be found" if disk.nil?

      snapshot_url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_SNAPSHOTS, resource_group_name: resource_group_name, name: snapshot_name)
      # By default, the snapshot sku is Standard_LRS. TODO: should the snapshot use the disk sku?
      snapshot = {
        'location' => disk[:location],
        'tags' => params[:tags],
        'properties' => {
          'creationData' => {
            'createOption' => 'Copy',
            'sourceUri' => rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_DISKS, resource_group_name: resource_group_name, name: disk_name)
          }
        }
      }

      http_put(snapshot_url, snapshot)
    end

    # Get a (managed) snapshot's information
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] snapshot_name        - Name of snapshot.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    def get_managed_snapshot_by_name(resource_group_name, snapshot_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_SNAPSHOTS, resource_group_name: resource_group_name, name: snapshot_name)
      get_managed_snapshot(url)
    end

    # Get a (managed) snapshot's information
    # @param [String] url - URL of snapshot.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    #
    def get_managed_snapshot(url)
      result = get_resource_by_id(url)
      snapshot = nil
      unless result.nil?
        snapshot = {}
        snapshot[:id]       = result['id']
        snapshot[:name]     = result['name']
        snapshot[:location] = result['location']
        snapshot[:tags]     = result['tags']

        properties = result['properties']
        snapshot[:provisioning_state] = properties['provisioningState']
        snapshot[:disk_size]          = properties['diskSizeGB']
      end
      snapshot
    end

    # Delete a snapshot of managed disk
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of snapshot.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/DiskRP/stable/2021-04-01/disk.json
    #
    #
    def delete_managed_snapshot(resource_group_name, name)
      @logger.debug("delete_managed_snapshot - trying to delete '#{name}' from resource group '#{resource_group_name}'")
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_SNAPSHOTS, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Compute/Platform Images

    # List all versions of a specified platform image
    # @param [String] location  - The location where the platform image exists.
    # @param [String] publisher - The publisher of the platform image.
    # @param [String] offer     - The offer from the publisher.
    # @param [String] sku       - The sku of the publisher's offer.
    #
    # @return [Array]
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/compute/resource-manager/Microsoft.Compute/ComputeRP/stable/2021-04-01/compute.json
    #
    def list_platform_image_versions(location, publisher, offer, sku)
      images = []
      url =  "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      url += "/providers/#{REST_API_PROVIDER_COMPUTE}"
      url += "/locations/#{location}"
      url += "/publishers/#{publisher}"
      url += "/artifacttypes/#{REST_API_VM_IMAGE}"
      url += "/offers/#{offer}"
      url += "/skus/#{sku}"
      url += '/versions'

      result = get_resource_by_id(url)
      result&.each do |value|
        image = parse_platform_image(value)
        images << image
      end
      images
    end

    # Network/Public IP

    # Create a public IP
    # @param [String] resource_group_name      - Name of resource group.
    # @param [Hash] params                     - Parameters of public ip.
    #
    # ==== params
    # * +:name+                                - String. Name of public IP.
    # * +:location+                            - String. Location where the public IP will be created.
    # * +:is_static+                           - Boolean. Whether the IP address is static or dynamic.
    # * +:idle_timeout_in_minutes+             - Integer. Timeout for the TCP idle connection. The value can be set between 4 and 30 minutes.
    # When public IP is in an availability zone
    # * +:zone+                                - String. Zone number in string. Possible values: "1", "2" or "3".
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/create-or-update-a-public-ip-address
    #
    def create_public_ip(resource_group_name, params)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_PUBLIC_IP_ADDRESSES, resource_group_name: resource_group_name, name: params[:name])

      public_ip = {
        'name' => params[:name],
        'location' => params[:location],
        'properties' => {
          'publicIPAllocationMethod' => params[:is_static] ? 'Static' : 'Dynamic',
          'idleTimeoutInMinutes' => params[:idle_timeout_in_minutes]
        }
      }
      if params[:zone]
        public_ip['zones'] = [params[:zone]]
        public_ip['sku'] = { 'name' => 'Standard' }
        public_ip['properties']['publicIPAllocationMethod'] = 'Static'
      end

      http_put(url, public_ip)
    end

    # Get a public IP's information
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] name                 - Name of public IP.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-public-ip-address
    #
    def get_public_ip_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_PUBLIC_IP_ADDRESSES, resource_group_name: resource_group_name, name: name)
      get_public_ip(url)
    end

    # Get a public IP's information
    # @param [String] url - URL of public IP.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-public-ip-address
    #
    def get_public_ip(url)
      result = get_resource_by_id(url)
      parse_public_ip(result)
    end

    # List all public IPs within a specified resource group
    # @param [String] resource_group_name - Name of resource group.
    #
    # @return [Array]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/list-public-ip-addresses-within-a-resource-group
    #
    def list_public_ips(resource_group_name)
      ip_addresses = []
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_PUBLIC_IP_ADDRESSES, resource_group_name: resource_group_name)
      result = get_resource_by_id(url)
      unless result.nil?
        result['value'].each do |ret|
          ip_address = parse_public_ip(ret)
          ip_addresses.push(ip_address)
        end
      end
      ip_addresses
    end

    # Delete a public IP
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] name                - Name of public IP.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/delete-a-public-ip-address
    #
    def delete_public_ip(resource_group_name, name)
      @logger.debug("delete_public_ip - trying to delete #{name} from resource group #{resource_group_name}")
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_PUBLIC_IP_ADDRESSES, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Network/Load Balancer

    # Get a load balancer's information
    # @param [String,nil] resource_group_name - The load balancer's resource group name.
    # @param [String] name - Name of load balancer.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/load-balancer/loadbalancers/get
    #
    def get_load_balancer_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_LOAD_BALANCERS, resource_group_name: resource_group_name, name: name)
      _get_load_balancer(url)
    end

    # Get a load balancer's information
    # @param [String] url - URL of load balancer.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/load-balancer/loadbalancers/get
    #
    def _get_load_balancer(url)
      load_balancer = nil
      # see: https://docs.microsoft.com/en-us/rest/api/load-balancer/load-balancers/get#loadbalancer
      result = get_resource_by_id(url)
      unless result.nil?
        load_balancer = {}
        load_balancer[:id] = result['id']
        load_balancer[:name] = result['name']
        load_balancer[:location] = result['location']
        load_balancer[:tags] = result['tags']
        properties = result['properties']
        load_balancer[:provisioning_state] = properties['provisioningState']

        frontend = properties['frontendIPConfigurations']
        load_balancer[:frontend_ip_configurations] = []
        frontend.each do |frontend_ip|
          ip = {}
          ip[:name]                         = frontend_ip['name']
          ip[:id]                           = frontend_ip['id']
          ip[:provisioning_state]           = frontend_ip['properties']['provisioningState']
          ip[:private_ip_allocation_method] = frontend_ip['properties']['privateIPAllocationMethod']
          ip[:private_ip]                   = frontend_ip['properties']['privateIPAddress'] unless frontend_ip['properties']['privateIPAddress'].nil?
          ip[:public_ip]                    = get_public_ip(frontend_ip['properties']['publicIPAddress']['id']) unless frontend_ip['properties']['publicIPAddress'].nil?
          ip[:inbound_nat_rules]            = frontend_ip['properties']['inboundNatRules']
          load_balancer[:frontend_ip_configurations].push(ip)
        end

        # see: https://docs.microsoft.com/en-us/rest/api/load-balancer/load-balancers/get#backendaddresspool
        backend = properties['backendAddressPools']
        load_balancer[:backend_address_pools] = []
        backend.each do |backend_ip|
          ip = {}
          ip[:name]                         = backend_ip['name']
          ip[:id]                           = backend_ip['id']
          ip[:provisioning_state]           = backend_ip['properties']['provisioningState']
          ip[:backend_ip_configurations]    = backend_ip['properties']['backendIPConfigurations']
          load_balancer[:backend_address_pools].push(ip)
        end
      end
      load_balancer
    end

    # Network/Network Interface

    # Create a network interface based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [String] resource_group_name - Name of resource group.
    # @param [Hash] nic_params            - Parameters for creating the network interface.
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of network interface.
    # * +:location+                     - String. The location where the network interface will be created.
    # * +:tags                          - Hash. The tags of the network interface.
    # * +:enable_ip_forwarding          - Boolean. Indicates whether IP forwarding is enabled on this network interface.
    # * +:enable_accelerated_networking - Boolean. Indicates whether accelerated networking is enabled on this network interface.
    # * +:ipconfig_name+                - String. The name of ipConfigurations for the network interface.
    # * +:private_ip                    - String. Private IP address which the network interface will use.
    # * +:public_ip                     - Hash. The public IP which the network interface is bound to.
    # * +:subnet                        - Hash. The subnet which the network interface is bound to.
    # * +:dns_servers                   - Array. DNS servers.
    # * +:network_security_group        - Hash. The network security group which the network interface is bound to.
    # * +:application_security_groups   - Array. The application security groups which the network interface is bound to.
    # * +:load_balancers                - Array<Hash>. The load balancers which the network interface is bound to. (see: Bosh::AzureCloud::VMManager._get_load_balancers)
    # * +:application_gateways          - Array<Hash>. The application gateways which the network interface is bound to. (see: Bosh::AzureCloud::VMManager._get_application_gateways)
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/create-or-update-a-network-interface-card
    #
    def create_network_interface(resource_group_name, nic_params)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, resource_group_name: resource_group_name, name: nic_params[:name])

      interface = {
        'name' => nic_params[:name],
        'location' => nic_params[:location],
        'tags' => nic_params[:tags],
        'properties' => {
          'networkSecurityGroup' => nic_params[:network_security_group].nil? ? nil : { 'id' => nic_params[:network_security_group][:id] },
          'enableIPForwarding' => nic_params[:enable_ip_forwarding],
          'enableAcceleratedNetworking' => nic_params[:enable_accelerated_networking],
          'ipConfigurations' => [
            {
              'name' => nic_params[:ipconfig_name],
              'properties' => {
                'privateIPAddress' => nic_params[:private_ip],
                'privateIPAllocationMethod' => nic_params[:private_ip].nil? ? 'Dynamic' : 'Static',
                'publicIPAddress' => nic_params[:public_ip].nil? ? nil : { 'id' => nic_params[:public_ip][:id] },
                'subnet' => {
                  'id' => nic_params[:subnet][:id]
                }
              }
            }
          ],
          'dnsSettings' => {
            'dnsServers' => nic_params[:dns_servers].nil? ? [] : nic_params[:dns_servers]
          }
        }
      }

      application_security_groups = []
      asg_params = nic_params.fetch(:application_security_groups, [])
      asg_params.each do |asg_param|
        application_security_groups.push('id' => asg_param[:id])
      end
      interface['properties']['ipConfigurations'][0]['properties']['applicationSecurityGroups'] = application_security_groups unless application_security_groups.empty?

      # see: Bosh::AzureCloud::VMManager._get_load_balancers
      load_balancers = nic_params[:load_balancers]
      unless load_balancers.nil?
        backend_pools = load_balancers.map { |load_balancer| { id: load_balancer[:backend_address_pools][0][:id] } }
        inbound_nat_rules = load_balancers.flat_map { |load_balancer| load_balancer[:frontend_ip_configurations][0][:inbound_nat_rules] }.compact
        interface['properties']['ipConfigurations'][0]['properties']['loadBalancerBackendAddressPools'] = backend_pools
        interface['properties']['ipConfigurations'][0]['properties']['loadBalancerInboundNatRules'] = inbound_nat_rules
      end

      # see: Bosh::AzureCloud::VMManager._get_application_gateways
      application_gateways = nic_params[:application_gateways]
      unless application_gateways.nil?
        # NOTE: backend_address_pools[0] should always be used. (When `application_gateway/backend_pool_name` is specified, the named pool will always be first here.)
        backend_pools = application_gateways.map { |application_gateway| { id: application_gateway[:backend_address_pools][0][:id] } }
        interface['properties']['ipConfigurations'][0]['properties']['applicationGatewayBackendAddressPools'] = backend_pools
      end

      http_put(url, interface)
    end

    # Get a network interface's information
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] name                - Name of network interface.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-network-interface-card
    #
    def get_network_interface_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, resource_group_name: resource_group_name, name: name)
      get_network_interface(url)
    end

    # Get a network interface's information
    # @param [String] url - URL of network interface..
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-network-interface-card
    #
    def get_network_interface(url)
      result = get_resource_by_id(url)
      parse_network_interface(result)
    end

    # List network interfaces whose name contains a keyword
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] keyword             - Keyword of network interfaces to list. keyword stands for a VM, and NICs of that VM are "#{keyword}-0", "#{keyword}-1" and so on.
    #
    # @return [Array] - Array of network interfaces, however, the network interface here will not contain details about public ip or load balancer.
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/list-network-interface-cards-within-a-resource-group
    #
    def list_network_interfaces_by_keyword(resource_group_name, keyword)
      network_interfaces = []
      network_interfaces_url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, resource_group_name: resource_group_name)
      results = get_resources_by_url(network_interfaces_url)
      unless results.nil? || results['value'].nil?
        results['value'].each do |network_interface_spec|
          network_interfaces.push(parse_network_interface(network_interface_spec, recursive: false)) if network_interface_spec['name'].include?(keyword)
        end
      end
      @logger.debug("list_network_interfaces_by_keyword: #{network_interfaces}")
      network_interfaces
    end

    # Delete a network interface
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] name                - Name of network interface.
    #
    # @return [Boolean]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/delete-a-network-interface-card
    #
    def delete_network_interface(resource_group_name, name)
      @logger.debug("delete_network_interface - trying to delete #{name} from resource group #{resource_group_name}")
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, resource_group_name: resource_group_name, name: name)
      http_delete(url)
    end

    # Network/Virtual Network

    # Get a virtual network's information
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] vnet_name           - Name of network.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/virtualnetwork/get-information-about-a-virtual-network
    #
    def get_virtual_network_by_name(resource_group_name, vnet_name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_VIRTUAL_NETWORKS, resource_group_name: resource_group_name, name: vnet_name)
      get_virtual_network(url)
    end

    # Get a virutal network's information
    # @param [String] url - URL of virtual network.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/virtualnetwork/get-information-about-a-virtual-network
    #
    def get_virtual_network(url)
      vnet = nil
      result = get_resource_by_id(url)
      unless result.nil?
        vnet = {}
        vnet[:id]   = result['id']
        vnet[:name] = result['name']
        vnet[:location] = result['location']

        properties = result['properties']
        vnet[:provisioning_state] = properties['provisioningState']
        vnet[:address_space] = properties['addressSpace']
        vnet[:subnets] = []
        properties['subnets'].each do |subnet|
          vnet[:subnets].push(parse_subnet(subnet))
        end
      end
      vnet
    end

    # Network/Subnet

    # Get a network subnet's information
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] vnet_name           - Name of network.
    # @param [String] subnet_name         - Name of network subnet.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/create-or-update-a-subnet
    #
    def get_network_subnet_by_name(resource_group_name, vnet_name, subnet_name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_VIRTUAL_NETWORKS, resource_group_name: resource_group_name, name: vnet_name, others: "subnets/#{subnet_name}")
      get_network_subnet(url)
    end

    # Get a network subnet's information
    # @param [String] url - URL of network subnet.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-subnet
    #
    def get_network_subnet(url)
      result = get_resource_by_id(url)
      parse_subnet(result)
    end

    # Network/Application Gateway

    # Get an application gateway's information
    # @param [String,nil] resource_group_name - The application gateway's resource group name.
    # @param [String] name - Name of application gateway.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/application-gateway/applicationgateways/get
    #
    def get_application_gateway_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_APPLICATION_GATEWAYS, resource_group_name: resource_group_name, name: name)
      get_application_gateway(url)
    end

    # Get an application gateway's information
    # @param [String] url - URL of application gateway.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/application-gateway/applicationgateways/get
    #
    def get_application_gateway(url)
      application_gateway = nil
      # see: https://docs.microsoft.com/en-us/rest/api/application-gateway/application-gateways/get#applicationgateway
      result = get_resource_by_id(url)
      unless result.nil?
        application_gateway = {}
        application_gateway[:id] = result['id']
        application_gateway[:name] = result['name']
        application_gateway[:location] = result['location']
        application_gateway[:tags] = result['tags']

        properties = result['properties']
        # see: https://docs.microsoft.com/en-us/rest/api/application-gateway/application-gateways/get#applicationgatewaybackendaddresspool
        backend = properties['backendAddressPools']
        application_gateway[:backend_address_pools] = []
        backend.each do |backend_ip|
          ip = {}
          ip[:name]                      = backend_ip['name']
          ip[:id]                        = backend_ip['id']
          ip[:provisioning_state]        = backend_ip['properties']['provisioningState']
          ip[:backend_ip_configurations] = backend_ip['properties']['backendIPConfigurations']
          application_gateway[:backend_address_pools].push(ip)
        end
      end
      application_gateway
    end

    # Network/Network Security Group

    # Get a network security group's information
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] name                - Name of network security group.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-network-security-group
    #
    def get_network_security_group_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_SECURITY_GROUPS, resource_group_name: resource_group_name, name: name)
      get_network_security_group(url)
    end

    # Get a network security group's information
    # @param [String] url - URL of network security group.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/network/get-information-about-a-network-security-group
    #
    def get_network_security_group(url)
      nsg = nil
      result = get_resource_by_id(url)
      unless result.nil?
        nsg = {}
        nsg[:id]   = result['id']
        nsg[:name] = result['name']
        nsg[:location] = result['location']
        nsg[:tags] = result['tags']

        properties = result['properties']
        nsg[:provisioning_state] = properties['provisioningState']
      end
      nsg
    end

    # Network/Application Security Group

    # Get a application security group's information
    # @param [String] resource_group_name - Name of resource group.
    # @param [String] name                - Name of application security group.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/virtualnetwork/applicationsecuritygroups/get
    #
    def get_application_security_group_by_name(resource_group_name, name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_APPLICATION_SECURITY_GROUPS, resource_group_name: resource_group_name, name: name)
      get_application_security_group(url)
    end

    # Get a application security group's information
    # @param [String] url - URL of application security group.
    #
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/virtualnetwork/applicationsecuritygroups/get
    #
    def get_application_security_group(url)
      asg = nil
      result = get_resource_by_id(url)
      unless result.nil?
        asg = {}
        asg[:id]   = result['id']
        asg[:name] = result['name']
        asg[:location] = result['location']
        asg[:tags] = result['tags']

        properties = result['properties']
        asg[:provisioning_state] = properties['provisioningState']
      end
      asg
    end

    # Storage/StorageAccounts

    # Create a storage account
    # @param [String] name     - Name of storage account.
    # @param [String] location - Location where the storage account will be created.
    # @param [String] sku      - SKU of storage account. In older versions, sku name was called accountType.
    #                            Options: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    # @param [String] kind     - Kind of storage account.
    # @param [Hash]   tags     - Tags of storage account.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def create_storage_account(name, location, sku, kind, tags)
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name: name)
      storage_account = {
        'location' => location,
        'sku' => {
          'name' => sku
        },
        'kind' => kind,
        'tags' => tags
      }

      uri = http_url(url)
      @logger.info("create_storage_account - trying to put '#{uri}'")

      request = Net::HTTP::Put.new(uri.request_uri)
      request_body = storage_account.to_json
      request.body = request_body
      request['Content-Length'] = request_body.size
      @logger.debug("create_storage_account - request body:\n#{redact_credentials_in_request_body(storage_account)}")

      retry_count = 0
      begin
        retry_after = 10
        response = http_get_response(uri, request, retry_after)
        if response.code.to_i == HTTP_CODE_OK
          return true
        elsif response.code.to_i != HTTP_CODE_ACCEPTED
          raise AzureError, "create_storage_account - Cannot create the storage account '#{name}'. http code: #{response.code}. Error message: #{response.body}"
        end

        uri = URI(response['Location'])
        api_version = get_api_version(@azure_config, AZURE_RESOURCE_PROVIDER_STORAGE)
        check_status_request = Net::HTTP::Get.new(uri.request_uri)
        check_status_request.add_field('x-ms-version', api_version)
        loop do
          retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
          sleep(retry_after)
          @logger.debug("create_storage_account - Checking the status of the asynchronous operation using '#{uri}' after '#{retry_after}' seconds.")
          response = http_get_response(uri, check_status_request, retry_after)

          status_code = response.code.to_i
          if status_code == HTTP_CODE_OK
            # Need to check status in response body for asynchronous operation even if status_code is HTTP_CODE_OK.
            # Ignore exception if the body of the response is not JSON format
            result = nil
            ignore_exception { result = JSON(response.body) } unless response.body.nil? || response.body.empty?
            if !result.nil? && result['status'] == PROVISIONING_STATE_FAILED
              error = "create_storage_account - http code: #{response.code}\n"
              error += get_http_common_headers(response)
              error += "Error message: #{response.body}"
              if response.key?('Retry-After')
                retry_after = response['Retry-After'].to_i
                @logger.warn("create_storage_account - Fail for an AzureAsynInternalError. Will retry after #{retry_after} seconds.")
                sleep(retry_after)
                raise AzureAsynInternalError, error
              end
              raise AzureAsynchronousError.new(result['status']), error
            end
            return true
          elsif status_code != HTTP_CODE_ACCEPTED
            error = "create_storage_account - http code: #{response.code}. Error message: #{response.body}"
            @logger.error(error)
            raise AzureAsynchronousError.new, error
          end
        end
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    # Check that account name is valid and is not already in use.
    # @param [String] name - Name of storage account.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def check_storage_account_name_availability(name)
      url =  "/subscriptions/#{uri_escape(@azure_config.subscription_id)}"
      url += "/providers/#{REST_API_PROVIDER_STORAGE}"
      url += '/checkNameAvailability'
      storage_account = {
        'name' => name,
        'type' => "#{REST_API_PROVIDER_STORAGE}/#{REST_API_STORAGE_ACCOUNTS}"
      }
      result = http_post(url, storage_account)
      raise AzureError, "Cannot check the availability of the storage account name '#{name}'" unless result.is_a?(Hash)

      {
        available: result['nameAvailable'],
        reason: result['reason'],
        message: result['message']
      }
    end

    # Get a storage account's information
    # @param [String] name - Name of storage account.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def get_storage_account_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name: name)
      get_storage_account(url)
    end

    # Get a storage account's information
    # @param [String] url - URL of storage account.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def get_storage_account(url)
      result = get_resource_by_id(url)
      parse_storage_account(result)
    end

    # Get access keys of a storage account
    # @param [String] name - Name of storage account.
    #
    # @return [Hash]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def get_storage_account_keys_by_name(name)
      result = nil
      begin
        url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name: name, others: 'listKeys')
        result = http_post(url)
      rescue AzureNotFoundError => e
        result = nil
      end

      keys = []
      unless result.nil?
        result['keys'].each do |key|
          keys << key['value']
        end
      end
      keys
    end

    # List storage accounts within the default resource group
    #
    # @return [Array]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def list_storage_accounts
      storage_accounts = []
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS)
      result = get_resource_by_id(url)
      unless result.nil?
        result['value'].each do |value|
          storage_account = parse_storage_account(value)
          storage_accounts << storage_account
        end
      end
      storage_accounts
    end

    # Set tags for a storage account
    # @param [String] name - Name of storage account.
    # @param [Hash] tags   - tags key/value pairs.
    #
    # @return [Boolean]
    #
    # @See https://github.com/Azure/azure-rest-api-specs/blob/master/specification/storage/resource-manager/Microsoft.Storage/stable/2017-10-01/storage.json
    #
    def update_tags_of_storage_account(name, tags)
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name: name)
      request_body = {
        tags: tags
      }
      http_patch(url, request_body)
    end

    def get_max_fault_domains_for_location(location)
      resource_skus = list_resource_skus(location, REST_API_AVAILABILITY_SETS)
      sku_for_location = resource_skus.find { |sku| sku[:name] == 'Aligned' }

      raise "Unable to get maximum fault domains for location '#{location}'" unless sku_for_location &&
            sku_for_location[:capabilities] &&
            sku_for_location[:capabilities].key?(:MaximumPlatformFaultDomainCount)

      sku_for_location[:capabilities][:MaximumPlatformFaultDomainCount].to_i
    end

    # Create or Update a Compute Gallery Image Definition
    #
    # @param [String] gallery_name - Name of gallery.
    # @param [String] image_definition - Name of gallery image.
    # @param [Hash] params - Parameters for creating the gallery image definition.
    # ==== Params
    # Required key/value pairs are:
    # * +:location+ - String. The location where the gallery image definition will be created.
    # * +:publisher+ - String. The publisher of the image definition.
    # * +:offer+ - String. The offer of the image definition.
    # * +:sku+ - String. The sku of the image definition.
    # * +:osType+ - String. The osType of the image definition.
    # Optional key/value pairs are:
    # * +:tags+ - Hash. The tags of the gallery image definition.
    # * +:hyperVGeneration+ - String. The hyperVGeneration of the image definition.
    #
    # @See https://learn.microsoft.com/en-us/rest/api/compute/gallery-images/create-or-update?view=rest-compute-2024-07-01&tabs=HTTP
    #
    def create_gallery_image_definition(gallery_name, image_definition, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_GALLERIES, name: gallery_name) + "/#{REST_API_IMAGES}/#{image_definition}"

      required_params = %w(location publisher offer sku osType)
      required_params.each do |param|
        raise ArgumentError, "Missing required parameter '#{param}'" unless params.key?(param)
      end

      image_definition_params = {
        'location' => params['location'],
        'tags' => params['tags'],
        'properties' => {
          'identifier' => {
            'publisher' => params['publisher'],
            'offer' => params['offer'],
            'sku' => params['sku'],
          },
          'osState' => 'Generalized',
          'osType' => params['osType'],
          'hyperVGeneration' => params.fetch('hyperVGeneration', 'V1')
        }
      }.compact
      image_definition_params['properties'].compact!

      @logger.debug("Creating / updating new gallery image definition: '#{url}' with params: #{image_definition_params}")
      http_put(url, image_definition_params, { 'api-version' => '2024-03-03' })
    end

    # Create or Update a Compute Gallery Image Version
    #
    # @param [String] gallery_name - Name of gallery.
    # @param [String] image_definition - Name of gallery image.
    # @param [String] version - Name of gallery image version.
    # @param [Hash] params - Parameters for creating the gallery image version.
    # ==== Params
    # Required key/value pairs are:
    # * +:location+             - String. The location where the gallery image version will be created.
    # * +:blob_uri+             - String. The blob uri of the image version.
    # * +:storage_account_name+ - String. The storage account name of the image version.
    # * +:image_id+             - String. The image id of the image version.
    # Optional key/value pairs are:
    # * +:tags+ - Hash. The tags of the gallery image version.
    #
    # @See https://learn.microsoft.com/en-us/rest/api/compute/gallery-image-versions/create-or-update?view=rest-compute-2024-11-04&tabs=HTTP
    #
    def create_gallery_image_version(gallery_name, image_definition, version, params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_GALLERIES, name: gallery_name) + "/#{REST_API_IMAGES}/#{image_definition}/versions/#{version}"

      raise ArgumentError, "Missing required parameter 'location'" unless params.key?('location')

      profile = {}
      if params.key?('blob_uri') && params.key?('storage_account_name')
        profile['osDiskImage'] = {
          'source' => {
              'id' => rest_api_url(REST_API_PROVIDER_STORAGE, 'storageAccounts', name: params['storage_account_name']),
              'uri' => params['blob_uri']
          }
        }
      end

      replica_count = params['replica_count'] || 1
      target_regions = (params['target_regions'] || [params['location']]).map { |r| { 'name' => r } }
      image_version_params = {
        'location' => params['location'],
        'tags' => params['tags'],
        'properties' => {
          'publishingProfile' => {
            'replicaCount' => replica_count,
            'targetRegions' => target_regions
          },
          'storageProfile' => profile,
        },
      }.compact

      @logger.debug("Creating / updating new gallery image version: '#{url}' with params: #{image_version_params}")
      response = http_put(url, image_version_params, { 'api-version' => '2024-03-03' })
      result = JSON.parse(response.body, symbolize_keys: false) unless response.body.nil? || response.body == ''

      parse_gallery_image(result)
    end

    # Delete a gallery image version
    #
    # @param [String] gallery_name - Name of gallery.
    # @param [String] image_definition - Name of gallery image.
    # @param [String] version - Name of gallery image version.
    # @return [Boolean]
    # @raise [AzureError] if the operation fails
    #
    # @See https://learn.microsoft.com/en-us/rest/api/compute/gallery-image-versions/delete?view=rest-compute-2024-07-01&tabs=HTTP
    #
    def delete_gallery_image_version(gallery_name, image_definition, version)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_GALLERIES, name: gallery_name) + "/#{REST_API_IMAGES}/#{image_definition}/versions/#{version}"

      @logger.debug("Deleting gallery image version '#{version}' in the gallery image '#{image_definition}' of the gallery '#{gallery_name}'")
      http_delete(url)
    end

    # Get a gallery image version by searching for matching tags
    #
    # @param [String] gallery_name - Name of gallery.
    # @param [Hash] tags - Tags to match against gallery image version tags.
    # @return [Hash,nil] The gallery image version that matches the tags
    #
    # @See https://learn.microsoft.com/en-us/rest/api/resources/resources/list
    #
    def get_gallery_image_version_by_tags(gallery_name, tags)
      @logger.debug("Searching in gallery '#{gallery_name}' for images with tags: #{tags}")
      return nil if gallery_name.nil? || gallery_name.empty?

      tag_filters = tags.map { |key, value| "tagName eq '#{key}' and tagValue eq '#{value}'" }.join(' and ')
      url = "/subscriptions/#{@azure_config.subscription_id}/resourceGroups/#{@azure_config.resource_group_name}/resources"
      result = get_resource_by_id(url, {'$filter' => tag_filters})
      return nil if result.nil? || result['value'].nil?

      matching_resource =
        result['value'].find do |resource|
          resource['type'] == "#{REST_API_PROVIDER_COMPUTE}/#{REST_API_GALLERIES}/#{REST_API_IMAGES}/versions"
        end
      return nil unless matching_resource

      # As the resource does not contain the targetRegion, we need to do one more request to get the full resource
      image_version = get_resource_by_id(matching_resource['id'])
      parse_gallery_image(image_version)
    end

    # List available Resource SKUs by Location and resource type. The list is updated at least once a day.
    #
    # @param [String] location - The location to list the resource SKUs.
    # @param [String] resource_type - The resource type to filter the SKUs.
    # @return [Array] The list of available Resource SKUs
    #
    # @See https://learn.microsoft.com/en-us/rest/api/compute/resource-skus/list?view=rest-compute-2024-11-04&tabs=HTTP
    #
    def list_resource_skus(location=nil, resource_type=nil)
      cache_key = "skus_#{location || 'all'}_#{resource_type || 'all'}.json"
      full_cache_dir = File.join(CACHE_DIR, CACHE_SUBDIR)
      cache_file = File.join(full_cache_dir, cache_key)

      if File.exist?(cache_file) && (Time.now - File.mtime(cache_file)) < CACHE_EXPIRY_SECONDS
        @logger.debug("list_resource_skus - Reading from cache file: #{cache_file}")
        begin
          cached_data = JSON.parse(File.read(cache_file), symbolize_names: true)
          return cached_data
        rescue JSON::ParserError => e
          @logger.warn("list_resource_skus - Failed to parse cache file #{cache_file}: #{e.message}. Fetching fresh data.")
        rescue StandardError => e
          @logger.warn("list_resource_skus - Failed to read cache file #{cache_file}: #{e.message}. Fetching fresh data.")
        end
      else
         @logger.debug("list_resource_skus - Cache miss or expired for key: #{cache_key}. Fetching from API.")
      end

      url = "/subscriptions/#{uri_escape(@azure_config.subscription_id)}/providers/#{REST_API_PROVIDER_COMPUTE}/skus"
      params = {}
      params['$filter'] = "location eq '#{location}'" if location
      result = get_resource_by_id(url, params)
      resource_skus = []

      unless result.nil? || result['value'].nil?
        result['value'].each do |sku|
          next if resource_type && sku['resourceType'] != resource_type

          vm_sku = {
            name: sku['name'],
            resource_type: sku['resourceType'],
            location: sku['locations']&.first,
            tier: sku['tier'],
            size: sku['size'],
            family: sku['family'],
            restrictions: sku['restrictions'],
            capabilities: sku['capabilities']&.map { |c| [c['name'].to_sym, c['value']] }.to_h || {}
          }
          next if location && vm_sku[:location]&.downcase != location.downcase

          resource_skus << vm_sku
        end
      end

      if !Dir.exist?(CACHE_DIR)
        @logger.debug("list_resource_skus - Cache parent directory #{CACHE_DIR} does not exist. Skipping cache write.")
        return resource_skus
      end

      begin
        FileUtils.mkdir_p(full_cache_dir)
        File.open(cache_file, File::RDWR | File::CREAT) do |f|
          f.flock(File::LOCK_EX)
          begin
              f.truncate(0)
              f.write(JSON.pretty_generate(resource_skus))
              @logger.debug("list_resource_skus - Wrote data to cache file: #{cache_file}")
          ensure
            f.flock(File::LOCK_UN)
          end
        end
      rescue StandardError => e
        @logger.warn("list_resource_skus - Failed to write cache file #{cache_file}: #{e.message}")
      end

      resource_skus
    end

    # List available Resource SKUs for Virtual Machines by Location
    #
    # @param [String] location - The location to list the resource SKUs.
    # @return [Array] The list of available Resource SKUs
    def list_vm_skus(location)
      list_resource_skus(location, REST_API_VIRTUAL_MACHINES)
    end

    private

    # @return [Hash]
    def _parse_name_from_id(id)
      ret = id.match('/subscriptions/([^/]*)/resourceGroups/([^/]*)/providers/([^/]*)/([^/]*)/([^/]*)(.*)')
      raise AzureError, "\"#{id}\" is not a valid URL." if ret.nil?

      result = {}
      result[:subscription_id]     = ret[1]
      result[:resource_group_name] = ret[2]
      result[:provider_name]       = ret[3]
      result[:resource_type]       = ret[4]
      result[:resource_name]       = ret[5]
      result
    end

    # @return [Hash, nil]
    def parse_vm_size(result)
      vm_size = nil
      unless result.nil?
        vm_size = {}
        vm_size[:name]            = result['name']
        vm_size[:number_of_cores] = result['numberOfCores']
        vm_size[:memory_in_mb]    = result['memoryInMB']
      end
      vm_size
    end

    # @return [Hash, nil]
    def parse_managed_disk(result)
      managed_disk = nil

      unless result.nil?
        managed_disk = {}
        managed_disk[:id]        = result['id']
        managed_disk[:name]      = result['name']
        managed_disk[:location]  = result['location']
        managed_disk[:tags]      = result['tags']
        managed_disk[:sku_name]  = result['sku']['name']
        managed_disk[:sku_tier]  = result['sku']['tier']
        managed_disk[:zone]      = result['zones'][0] unless result['zones'].nil?
        properties = result['properties']
        managed_disk[:iops]      = properties['diskIOPSReadWrite']
        managed_disk[:mbps]      = properties['diskMBpsReadWrite']
        managed_disk[:provisioning_state] = properties['provisioningState']
        managed_disk[:disk_size]          = properties['diskSizeGB']
      end
      managed_disk
    end

    # @return [Hash, nil]
    def parse_user_image(result)
      user_image = nil
      unless result.nil?
        user_image = {}
        user_image[:id]       = result['id']
        user_image[:name]     = result['name']
        user_image[:location] = result['location']
        user_image[:tags]     = result['tags']
        properties = result['properties']
        user_image[:provisioning_state] = properties['provisioningState']
      end
      user_image
    end

    # @return [Hash, nil]
    def parse_platform_image(result)
      image = nil
      unless result.nil?
        image = {}
        image[:id]       = result['id']
        image[:name]     = result['name']
        image[:location] = result['location']
      end
      image
    end

    # @return [Hash, nil]
    def parse_gallery_image(result)
      image = nil
      unless result.nil?
        image = {}
        image[:id] = result['id']
        if result['id']&.include?('/images/')
          image[:gallery_name] = result['id'].split('/galleries/').last.split('/images/').first
          image[:image_definition] = result['id'].split('/images/').last.split('/versions/').first
        end
        image[:name]          = result['name']
        image[:location]      = result['location']
        image[:tags]          = result['tags']
        image[:replica_count] = result.dig('properties', 'publishingProfile', 'replicaCount')

        targetRegions = result.dig('properties', 'publishingProfile', 'targetRegions')
        image[:target_regions] = targetRegions.map { |h| h['name'] } unless targetRegions.nil?
      end
      image
    end

    # @return [Hash, nil]
    def parse_network_interface(result, recursive: true)
      interface = nil
      unless result.nil?
        interface = {}
        interface[:id] = result['id']
        interface[:name] = result['name']
        interface[:location] = result['location']
        interface[:tags] = result['tags']

        properties = result['properties']
        interface[:provisioning_state] = properties['provisioningState']

        interface[:enable_ip_forwarding] = properties['enableIPForwarding'] unless properties['enableIPForwarding'].nil?

        interface[:enable_accelerated_networking] = properties['enableAcceleratedNetworking'] unless properties['enableAcceleratedNetworking'].nil?

        unless properties['networkSecurityGroup'].nil?
          interface[:network_security_group] = if recursive
                                                 get_network_security_group(properties['networkSecurityGroup']['id'])
                                               else
                                                 { id: properties['networkSecurityGroup']['id'] }
                                               end
        end

        unless properties['dnsSettings']['dnsServers'].nil?
          interface[:dns_settings] = []
          properties['dnsSettings']['dnsServers'].each { |dns| interface[:dns_settings].push(dns) }
        end

        ip_configuration = properties['ipConfigurations'][0]
        interface[:ip_configuration_id] = ip_configuration['id']

        ip_configuration_properties = ip_configuration['properties']
        interface[:private_ip] = ip_configuration_properties['privateIPAddress']
        interface[:private_ip_allocation_method] = ip_configuration_properties['privateIPAllocationMethod']
        unless ip_configuration_properties['publicIPAddress'].nil?
          interface[:public_ip] = if recursive
                                    get_public_ip(ip_configuration_properties['publicIPAddress']['id'])
                                  else
                                    { id: ip_configuration_properties['publicIPAddress']['id'] }
                                  end
        end
        load_balancer_backend_pools = ip_configuration_properties['loadBalancerBackendAddressPools']
        unless load_balancer_backend_pools.nil?
          load_balancers = load_balancer_backend_pools.map do |lb_backend_pool|
            if recursive
              names = _parse_name_from_id(lb_backend_pool['id'])
              load_balancer = get_load_balancer_by_name(names[:resource_group_name], names[:resource_name])
            else
              load_balancer = { id: lb_backend_pool['id'] }
            end
            load_balancer
          end
          interface[:load_balancers] = load_balancers
        end
        application_gateway_backend_pools = ip_configuration_properties['applicationGatewayBackendAddressPools']
        unless application_gateway_backend_pools.nil?
          application_gateways = application_gateway_backend_pools.map do |agw_backend_pool|
            if recursive
              names = _parse_name_from_id(agw_backend_pool['id'])
              application_gateway = get_application_gateway_by_name(names[:resource_group_name], names[:resource_name])
            else
              application_gateway = { id: agw_backend_pool['id'] }
            end
            application_gateway
          end
          interface[:application_gateways] = application_gateways
        end
        unless ip_configuration_properties['applicationSecurityGroups'].nil?
          asgs_properties = ip_configuration_properties['applicationSecurityGroups']
          asgs = []
          asgs_properties.each do |asg_property|
            if recursive
              asgs.push(get_application_security_group(asg_property['id']))
            else
              asgs.push(id: asg_property['id'])
            end
          end
          interface[:application_security_groups] = asgs
        end
      end
      interface
    end

    # @return [Hash, nil]
    def parse_subnet(result)
      subnet = nil
      unless result.nil?
        subnet = {}
        subnet[:id]   = result['id']
        subnet[:name] = result['name']

        properties = result['properties']
        subnet[:provisioning_state] = properties['provisioningState']
        subnet[:address_prefix]     = properties['addressPrefix']
      end
      subnet
    end

    # @return [Hash, nil]
    def parse_public_ip(result)
      ip_address = nil
      unless result.nil?
        ip_address = {}
        ip_address[:id]       = result['id']
        ip_address[:name]     = result['name']
        ip_address[:location] = result['location']
        ip_address[:tags]     = result['tags']
        ip_address[:sku]      = result['sku']['name'] unless result['sku'].nil?
        ip_address[:zone]     = result['zones'][0] unless result['zones'].nil?

        properties = result['properties']
        ip_address[:resource_guid]               = properties['resourceGuid']
        ip_address[:provisioning_state]          = properties['provisioningState']
        ip_address[:ip_address]                  = properties['ipAddress']
        ip_address[:public_ip_allocation_method] = properties['publicIPAllocationMethod']
        ip_address[:public_ip_address_version]   = properties['publicIPAddressVersion']
        ip_address[:idle_timeout_in_minutes]     = properties['idleTimeoutInMinutes']
        ip_address[:ip_configuration_id]         = properties['ipConfigurations']['id'] unless properties['ipConfigurations'].nil?
        unless properties['dnsSettings'].nil?
          ip_address[:domain_name_label] = properties['dnsSettings']['domainNameLabel']
          ip_address[:fqdn]              = properties['dnsSettings']['fqdn']
          ip_address[:reverse_fqdn]      = properties['dnsSettings']['reverseFqdn']
        end
      end
      ip_address
    end

    # @return [Hash, nil]
    def parse_storage_account(result)
      storage_account = nil
      unless result.nil?
        storage_account = {}
        storage_account[:id]       = result['id']
        storage_account[:name]     = result['name']
        storage_account[:location] = result['location']
        storage_account[:sku_name] = result['sku']['name']
        storage_account[:sku_tier] = result['sku']['tier']
        storage_account[:kind]     = result['kind']
        storage_account[:tags]     = result['tags']
        properties = result['properties']
        storage_account[:provisioning_state] = properties['provisioningState']
        storage_account[:storage_blob_host]  = properties['primaryEndpoints']['blob']
        storage_account[:storage_table_host] = properties['primaryEndpoints']['table'] if properties['primaryEndpoints'].key?('table')
      end
      storage_account
    end

    # @return [Boolean]
    def filter_credential_in_logs(uri)
      return true if !is_debug_mode(@azure_config) && uri.request_uri.include?('/listKeys')

      false
    end

    def redact_credentials(keys, hash)
      hash.map do |k, v|
        [k, if v.is_a?(Hash)
              redact_credentials(keys, v)
            else
              (keys.include?(k) ? '<redacted>' : v)
            end]
      end.to_h
    end

    # @return [String]
    def redact_credentials_in_request_body(body)
      is_debug_mode(@azure_config) ? body.to_json : redact_credentials(CREDENTIAL_KEYWORD_LIST, body).to_json
    end

    # @return [Object]
    def redact_credentials_in_response_body(body)
      is_debug_mode(@azure_config) ? body : redact_credentials(CREDENTIAL_KEYWORD_LIST, JSON.parse(body, symbolize_keys: false)).to_json
    rescue StandardError => e
      body
    end

    # @return [Net::HTTP]
    def http(uri, use_ssl = true)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true && use_ssl
      if @azure_config.environment == ENVIRONMENT_AZURESTACK && uri.host.include?(@azure_config.azure_stack.domain)
        # The CA cert is only specified for the requests to AzureStack domain. If specified for other domains, the request will fail.
        http.ca_file = get_ca_cert_path
      end
      # The default value for read_timeout is 60 seconds.
      # The default value for open_timeout is nil before ruby 2.3.0 so set it to 60 seconds here.
      http.open_timeout = 60
      http.set_debug_output($stdout) if is_debug_mode(@azure_config)
      http
    end

    def get_token(force_refresh = false)
      if @token.nil? || (Time.at(@token['expires_on'].to_i) - Time.new) <= 0 || force_refresh
        @logger.info('get_token - trying to get/refresh Azure authentication token')
        use_managed_identity = @azure_config.managed_identity_enabled?
        use_ssl = !use_managed_identity
        request, uri = use_managed_identity ? request_from_managed_identity_endpoint : request_from_azure_active_directory_endpoint
        retryable_error_codes = use_managed_identity ? AZURE_MANAGED_IDENTITY_TOKEN_RETRYABLE_ERROR_CODES : AZURE_AD_TOKEN_RETRYABLE_ERROR_CODES
        retry_count = 0
        max_retry_count = 5
        delay = 0
        max_delay = 60
        while retry_count < max_retry_count
          response = http_get_response_with_network_retry(http(uri, use_ssl), request)
          message = get_http_common_headers(response)
          @logger.debug("get_token - #{retry_count}: #{message}")
          status_code = response.code.to_i
          break unless retryable_error_codes.include?(status_code)

          retry_count += 1
          if retry_count >= max_retry_count
            cloud_error("get_token - Failed to get token after #{retry_count} retries")
          else
            # perform exponential backoff with a cap.
            # must increment retry_count before calculating delay.
            # the base value of 2 is the "delta backoff" as specified in the guidance doc.
            delay += 2**retry_count
            delay = max_delay if delay > max_delay
            @logger.debug("get_token - sleep #{delay} seconds before retrying")
            sleep(delay)
          end
        end

        case status_code
        when HTTP_CODE_OK
          @token = JSON(response.body)
        when HTTP_CODE_UNAUTHORIZED
          raise AzureError, "get_token - http code: #{status_code}. Azure authentication failed: Invalid tenant_id, client_id or client_secret/certificate. Error message: #{response.body}"
        when HTTP_CODE_BAD_REQUEST
          raise AzureError, "get_token - http code: #{status_code}. Azure authentication failed: Bad request. Please assure no typo in values of tenant_id, client_id or client_secret/certificate. Error message: #{response.body}"
        else
          raise AzureError, "get_token - http code: #{status_code}. Error message: #{response.body}"
        end
      end
      @token['access_token']
    end

    # https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-protocols-oauth-service-to-service
    def request_from_azure_active_directory_endpoint
      @logger.debug('Getting token from Azure Active Directory Endpoint')
      endpoint, api_version = get_azure_authentication_endpoint_and_api_version(@azure_config)
      uri = URI(endpoint)
      params = {
        'api-version' => api_version
      }
      uri.query = URI.encode_www_form(params)
      @logger.debug("authentication_endpoint: #{uri}")

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request = merge_http_common_headers(request)
      @logger.debug('request.header:')
      request.each_header { |k, v| @logger.debug("\t#{k} = #{v}") }

      client_id = @azure_config.client_id
      request_body = {
        'grant_type' => 'client_credentials',
        'client_id' => client_id,
        'resource' => get_token_resource(@azure_config),
        'scope' => 'user_impersonation'
      }
      if !@azure_config.client_secret.nil?
        request_body['client_secret'] = @azure_config.client_secret
      else
        request_body['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        request_body['client_assertion']      = get_jwt_assertion(endpoint, client_id)
      end
      request.body = URI.encode_www_form(request_body)
      @logger.debug("request body:\n#{redact_credentials_in_request_body(request_body)}")

      [request, uri]
    end

    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-http
    def request_from_managed_identity_endpoint
      @logger.debug('Getting token from Azure VM Managed Service Identity')
      endpoint, api_version = get_managed_identity_endpoint_and_version
      uri = URI(endpoint)
      params = {
        'resource' => get_token_resource(@azure_config),
        'api-version' => api_version
      }
      params['msi_res_id'] = @azure_config.managed_identity_resource_id unless @azure_config.managed_identity_resource_id.nil?
      uri.query = URI.encode_www_form(params)
      @logger.debug("authentication_endpoint: #{uri}")

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Metadata'] = true
      request = merge_http_common_headers(request)
      @logger.debug('request.header:')
      request.each_header { |k, v| @logger.debug("\t#{k} = #{v}") }

      [request, uri]
    end

    def http_url(url, params = {})
      unless params.key?('api-version')
        resource_provider = if url.include?(REST_API_PROVIDER_COMPUTE)
                              if url.include?(REST_API_DISKS)
                                AZURE_RESOURCE_PROVIDER_COMPUTE_DISK
                              elsif url.include?(REST_API_SNAPSHOTS)
                                AZURE_RESOURCE_PROVIDER_COMPUTE_SNAPSHOT
                              elsif url.include?(REST_API_GALLERIES)
                                AZURE_RESOURCE_PROVIDER_COMPUTE_GALLERY
                              else
                                AZURE_RESOURCE_PROVIDER_COMPUTE
                              end
                            elsif url.include?(REST_API_PROVIDER_NETWORK)
                              AZURE_RESOURCE_PROVIDER_NETWORK
                            elsif url.include?(REST_API_PROVIDER_STORAGE)
                              AZURE_RESOURCE_PROVIDER_STORAGE
                            else
                              AZURE_RESOURCE_PROVIDER_GROUP
                            end
        params['api-version'] = get_api_version(@azure_config, resource_provider)
      end
      uri = URI.join(get_arm_endpoint(@azure_config), url)
      uri.query = URI.encode_www_form(params)
      uri
    end

    def http_get_response(uri, request, retry_after)
      response = nil
      refresh_token = false
      retry_count = 0

      while retry_count < AZURE_MAX_RETRY_COUNT
        request['Content-Type']  = 'application/json'
        request['Authorization'] = 'Bearer ' + get_token(refresh_token)
        request = merge_http_common_headers(request)
        @logger.debug("http_get_response - #{retry_count}: #{request.method}, x-ms-client-request-id: #{request['x-ms-client-request-id']}, URI: #{uri}")
        response = http_get_response_with_network_retry(http(uri), request)

        status_code = response.code.to_i
        response_body = response.body
        message = "http_get_response - #{status_code}\n"
        message += get_http_common_headers(response)
        message += if filter_credential_in_logs(uri)
                     'response.body cannot be logged because it may contain credentials.'
                   elsif response_body && response_body.length > MAX_RESPONSE_BODY_LENGTH
                    'response.body is too long to be logged.'
                   else
                     "response.body: #{redact_credentials_in_response_body(response_body)}"
                   end
        @logger.debug(message)

        if status_code == HTTP_CODE_UNAUTHORIZED
          message = "http_get_response - Azure authentication failed: Token is invalid. Error message: #{response_body}"
          if refresh_token
            cloud_error(message)
          else
            @logger.debug(message)
            refresh_token = true
            next
          end
        end

        break unless AZURE_GENERAL_RETRYABLE_ERROR_CODES.include?(status_code)

        retry_count += 1
        if retry_count >= AZURE_MAX_RETRY_COUNT
          message += "http_get_response - Failed to get http response after #{AZURE_MAX_RETRY_COUNT} times.\n"
          cloud_error(message)
        else
          retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
          message += "http_get_response - Will retry after #{retry_after} seconds"
          @logger.debug(message)
          sleep(retry_after)
          refresh_token = false
        end
      end

      response
    end

    # Retry for the network errors
    def http_get_response_with_network_retry(http_handler, request)
      retry_count = 0
      retry_after = 5
      error_msg_format = 'http_get_response_with_network_retry - %{retry_count}: Will retry after %{retry_after} seconds due to an error %{error}'
      begin
        response = http_handler.request(request)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          @logger.warn(format(error_msg_format, retry_count: retry_count, retry_after: retry_after, error: e.class.name))
          sleep(retry_after)
          retry
        end
        raise e
      rescue OpenSSL::SSL::SSLError, OpenSSL::X509::StoreError => e
        if retry_count < AZURE_MAX_RETRY_COUNT && e.inspect.include?(ERROR_OPENSSL_RESET)
          retry_count += 1
          @logger.warn(format(error_msg_format, retry_count: retry_count, retry_after: retry_after, error: e.class.name))
          sleep(retry_after)
          retry
        end
        raise e
      rescue StandardError => e
        # Below error message depends on require "resolv-replace.rb" in lib/cloud/azure.rb
        if retry_count < AZURE_MAX_RETRY_COUNT
          if e.inspect.include?(ERROR_SOCKET_UNKNOWN_HOSTNAME)
            retry_count += 1
            @logger.warn(format(error_msg_format, retry_count: retry_count, retry_after: retry_after, error: 'DNS resolve error'))
            sleep(retry_after)
            retry
          elsif e.inspect.include?(ERROR_CONNECTION_REFUSED)
            retry_count += 1
            @logger.warn(format(error_msg_format, retry_count: retry_count, retry_after: retry_after, error: 'connection refused error'))
            sleep(retry_after)
            retry
          end
        end
        raise e
      end
    end

    def check_completion(response, options)
      operation_status_link = response['azure-asyncoperation']
      @logger.debug("check_completion - checking the status of the asynchronous operation using '#{operation_status_link}'")
      if options[:return_code].include?(response.code.to_i)
        if operation_status_link.nil?
          result = true
          ignore_exception { result = JSON(response.body) } unless response.body.nil? || response.body.empty?
          return result
        end
      elsif !options[:success_code].include?(response.code.to_i)
        error = "#{options[:operation]} - http code: #{response.code}\n"
        error += get_http_common_headers(response)
        error += "Error message: #{response.body}"
        raise AzureConflictError, error if response.code.to_i == HTTP_CODE_CONFLICT
        raise AzureNotFoundError, error if response.code.to_i == HTTP_CODE_NOT_FOUND

        raise AzureError, error
      end
      retry_after = options[:retry_after]
      operation_status_link.gsub!(' ', '%20')
      uri = URI(operation_status_link)
      params = {}
      params['api-version'] = options[:api_version]
      request = Net::HTTP::Get.new(uri.request_uri)
      uri.query = URI.encode_www_form(params)
      request.add_field('x-ms-version', options[:api_version])
      loop do
        retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
        sleep(retry_after)

        @logger.debug("check_completion - trying to get the status of asynchronous operation: #{uri}")
        response = http_get_response(uri, request, retry_after)
        status_code = response.code.to_i
        raise AzureAsynchronousError.new, "check_completion - http code: #{response.code}. Error message: #{response.body}" if status_code != HTTP_CODE_OK && status_code != HTTP_CODE_ACCEPTED

        raise AzureAsynchronousError.new, 'The body of the asynchronous response is empty' if response.body.nil? || response.body == ''

        result = JSON(response.body)
        raise AzureAsynchronousError.new, "The body of the asynchronous response does not contain 'status'. Response: #{response.body}" if result['status'].nil?

        status = result['status']
        case status
        when PROVISIONING_STATE_SUCCEEDED
          return true
        when PROVISIONING_STATE_INPROGRESS
          @logger.debug('check_completion - InProgress...')
        else
          error = "check_completion - http code: #{response.code}\n"
          error += get_http_common_headers(response)
          error += "Error message: #{response.body}"

          if status == PROVISIONING_STATE_FAILED && status_code == HTTP_CODE_OK && response.key?('Retry-After')
            retry_after = response['Retry-After'].to_i
            @logger.warn("check_completion - #{options[:operation]} fails for an AzureAsynInternalError. Will retry after #{retry_after} seconds.")
            sleep(retry_after)
            raise AzureAsynInternalError, error
          end

          raise AzureAsynchronousError.new(status), error
        end
      end
    end

    def http_get(uri, retry_after = 5)
      @logger.info("http_get - trying to get #{uri}")
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http_get_response(uri, request, retry_after)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_OK
        error = "http_get - http code: #{response.code}. Error message: #{response.body}"
        if [HTTP_CODE_NO_CONTENT, HTTP_CODE_NOT_FOUND].include? status_code
          raise AzureNotFoundError, error
        else
          raise AzureError, error
        end
      end
      response
    end

    def http_put(url, body = nil, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0
      response = nil

      begin
        @logger.info("http_put - #{retry_count}: trying to put #{uri}")

        request = Net::HTTP::Put.new(uri.request_uri)
        unless body.nil?
          request_body = body.to_json
          request.body = request_body
          request['Content-Length'] = request_body.size
          @logger.debug("http_put - request body:\n#{redact_credentials_in_request_body(body)}")
        end

        response = http_get_response(uri, request, retry_after)
        options = {
          operation: 'http_put',
          return_code: [HTTP_CODE_OK, HTTP_CODE_CREATED],
          success_code: [HTTP_CODE_CREATED, HTTP_CODE_ACCEPTED],
          api_version: params['api-version'],
          retry_after: retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end

      response
    end

    def http_patch(url, body = nil, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_patch - #{retry_count}: trying to patch #{uri}")

        request = Net::HTTP::Patch.new(uri.request_uri)
        unless body.nil?
          request_body = body.to_json
          request.body = request_body
          request['Content-Length'] = request_body.size
          @logger.debug("http_patch - request body:\n#{redact_credentials_in_request_body(body)}")
        end

        response = http_get_response(uri, request, retry_after)
        options = {
          operation: 'http_patch',
          return_code: [HTTP_CODE_OK],
          success_code: [HTTP_CODE_ACCEPTED],
          api_version: params['api-version'],
          retry_after: retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    def http_delete(url, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_delete - #{retry_count}: trying to delete #{uri}")

        request = Net::HTTP::Delete.new(uri.request_uri)
        response = http_get_response(uri, request, retry_after)
        options = {
          operation: 'http_delete',
          return_code: [HTTP_CODE_OK, HTTP_CODE_NO_CONTENT],
          success_code: [HTTP_CODE_ACCEPTED],
          api_version: params['api-version'],
          retry_after: retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    def http_post(url, body = nil, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_post - #{retry_count}: trying to post #{uri}")

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Length'] = 0
        unless body.nil?
          request_body = body.to_json
          request.body = request_body
          request['Content-Length'] = request_body.size
          @logger.debug("http_put - request body:\n#{redact_credentials_in_request_body(body)}")
        end
        response = http_get_response(uri, request, retry_after)
        options = {
          operation: 'http_post',
          return_code: [HTTP_CODE_OK],
          success_code: [HTTP_CODE_ACCEPTED],
          api_version: params['api-version'],
          retry_after: retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    def merge_http_common_headers(request)
      user_agents = ["#{USER_AGENT_FOR_REST}/#{Bosh::AzureCloud::VERSION}"]
      user_agents.push("pid-#{@azure_config.isv_tracking_guid}")
      request['User-Agent'] = user_agents.join(' ')
      # https://msdn.microsoft.com/en-us/library/mt766820.aspx
      # Caller-specified request ID, in the form of a GUID with no decoration such as curly braces.
      # If specified, this will be included in response information as a way to map the request.
      request['x-ms-client-request-id'] = SecureRandom.uuid
      # Indicates if a client-request-id should be returned in the response.
      request['x-ms-return-client-request-id'] = true
      request
    end

    def get_http_common_headers(response)
      message = "x-ms-client-request-id: #{response['x-ms-client-request-id']}\n"
      message += "x-ms-request-id: #{response['x-ms-request-id']}\n"
      message += "x-ms-correlation-request-id: #{response['x-ms-correlation-request-id']}\n"
      message += "x-ms-routing-request-id: #{response['x-ms-routing-request-id']}\n"
      message
    end

    # Sometimes Azure returns VM information with a node 'resources' which contains all extensions' information.
    # Azure will retrun 'InvalidRequestContent' if CPI does not delete the node 'resources'.
    # Similarly, the "content" of userAssignedIdentities (an object which may contain principalId and clientId keys) is invalid to send during an update
    # _sometimes_ resulting in a InvalidIdentityValues error
    def remove_resources_from_vm(vm)
      vm.delete('resources')
      if vm['identity'] && vm['identity']['type'] == 'UserAssigned'
        vm['identity']['userAssignedIdentities'] = vm['identity']['userAssignedIdentities'].keys.each_with_object({}) do |k, result|
          result[k] = {}
        end
      end
      vm
    end
  end
end
