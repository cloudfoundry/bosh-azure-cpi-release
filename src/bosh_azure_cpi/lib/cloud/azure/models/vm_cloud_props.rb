# frozen_string_literal: true

module Bosh::AzureCloud
  # https://bosh.io/docs/azure-cpi/#resource-pools
  class VMCloudProps
    include Helpers
    attr_accessor :instance_type
    attr_reader :instance_types
    attr_reader :root_disk, :ephemeral_disk, :caching
    attr_reader :availability_zone
    attr_reader :availability_set
    attr_reader :load_balancers
    attr_reader :application_gateways
    attr_reader :managed_identity
    attr_reader :security_group
    attr_reader :application_security_groups
    attr_reader :assign_dynamic_public_ip, :ip_forwarding, :accelerated_networking
    attr_reader :storage_account_name, :storage_account_type, :storage_account_kind, :storage_account_max_disk_number
    attr_reader :resource_group_name
    attr_reader :tags
    attr_reader :capacity_reservation_group
    attr_reader :capacity_reservation_group_id

    # Below defines are for test purpose
    # NOTE: The following 3 attr_writer (and their paired readers above) are explicitly separate (instead of using `attr_accessor`)
    #     since they are (as noted above) for testing only, and in case they need to be removed/hidden later.
    attr_writer :availability_zone
    attr_writer :availability_set
    attr_writer :assign_dynamic_public_ip

    AVAILABILITY_SET_KEY = 'availability_set'
    LOAD_BALANCER_KEY = 'load_balancer'
    APPLICATION_GATEWAY_KEY = 'application_gateway'
    BACKEND_POOL_NAME_KEY = 'backend_pool_name'
    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    NAME_KEY = 'name'

    def initialize(vm_properties, global_azure_config)
      @vm_properties = vm_properties.dup

      @instance_type = vm_properties['instance_type']
      @instance_types = vm_properties['instance_types']
      cloud_error("You need to specify one of 'vm_type/instance_type' or 'vm_resources'.") if @instance_type.nil? && (@instance_types.nil? || @instance_types.empty?)

      root_disk_hash = vm_properties.fetch('root_disk', {})
      @root_disk = Bosh::AzureCloud::RootDisk.new(
        root_disk_hash['size'],
        root_disk_hash['type'],
        _default_root_disk_placement(root_disk_hash['placement']),
        disk_encryption_set_name: root_disk_hash['disk_encryption_set_name']
      )

      cloud_error("Only one of 'type' and 'placement' is allowed to be configured for the root_disk when 'placement' is not set to persistent") if @root_disk.placement != 'remote' && !@root_disk.type.nil? && !global_azure_config.use_managed_disks

      ephemeral_disk_hash = vm_properties.fetch('ephemeral_disk', {})
      @ephemeral_disk = Bosh::AzureCloud::EphemeralDisk.new(
        ephemeral_disk_hash['use_root_disk'].nil? ? false : ephemeral_disk_hash['use_root_disk'],
        ephemeral_disk_hash['size'],
        ephemeral_disk_hash['type'],
        ephemeral_disk_hash['caching'],
        ephemeral_disk_hash['iops'],
        ephemeral_disk_hash['mbps'],
        disk_encryption_set_name: ephemeral_disk_hash['disk_encryption_set_name']
      )

      @caching = vm_properties.fetch('caching', 'ReadWrite')

      @availability_zone = vm_properties['availability_zone']
      unless @availability_zone.nil?
        cloud_error('Virtual Machines deployed to an Availability Zone must use managed disks') unless global_azure_config.use_managed_disks
        cloud_error("'#{@availability_zone}' is not a valid zone. Available zones are: #{AVAILABILITY_ZONES}") unless AVAILABILITY_ZONES.include?(@availability_zone.to_s)
      end
      @availability_set = _parse_availability_set_config(vm_properties, global_azure_config)
      cloud_error("Only one of 'availability_zone' and 'availability_set' is allowed to be configured for the VM but you have configured both.") if !@availability_zone.nil? && !@availability_set.name.nil?

      @load_balancers = _parse_load_balancer_config(vm_properties, global_azure_config)

      @application_gateways = _parse_application_gateway_config(vm_properties)

      @managed_identity = global_azure_config.default_managed_identity
      managed_identity_hash = vm_properties.fetch('managed_identity', nil)
      @managed_identity = Bosh::AzureCloud::ManagedIdentity.new(managed_identity_hash) unless managed_identity_hash.nil?

      @security_group = Bosh::AzureCloud::SecurityGroup.parse_security_group(vm_properties['security_group'])
      @application_security_groups = vm_properties['application_security_groups']

      @assign_dynamic_public_ip = vm_properties['assign_dynamic_public_ip']
      @ip_forwarding = vm_properties['ip_forwarding']
      @accelerated_networking = vm_properties['accelerated_networking']

      @storage_account_name = vm_properties['storage_account_name']
      @storage_account_kind = vm_properties.fetch('storage_account_kind', STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1)
      @storage_account_type = vm_properties['storage_account_type']
      @storage_account_max_disk_number = vm_properties.fetch('storage_account_max_disk_number', 30)

      @resource_group_name = vm_properties.fetch('resource_group_name', global_azure_config.resource_group_name)
      @tags = vm_properties.fetch('tags', {})

      @capacity_reservation_group     = vm_properties['capacity_reservation_group']
      @capacity_reservation_group_id  = vm_properties['capacity_reservation_group_id']
    end

    private

    # In Azure you can place your root disk at:
    #   temp disk   - resource-disk
    #   cache disk  - chache-disk
    #   persistent (default) - persistent os disk
    def _default_root_disk_placement(root_disk_placement)
      if root_disk_placement.nil?
        'remote'
      else
        valid_placements = %w[resource-disk cache-disk remote]
        cloud_error("root_disk 'placement' must be one of 'resource-disk','cache-disk','remote'") unless valid_placements.include?(root_disk_placement)
        root_disk_placement
      end
    end

    # In AzureStack, availability sets can only be configured with 1 update domain.
    # In Azure, the max update domain count of a managed/unmanaged availability set is 5.
    def _default_update_domain_count(global_azure_config)
      global_azure_config.environment == ENVIRONMENT_AZURESTACK ? 1 : 5
    end

    # In AzureStack, availability sets can only be configured with 1 fault domain and 1 update domain.
    # In Azure, the max fault domain count of an unmanaged availability set is 3;
    #           the max fault domain count of a managed availability set is 2 in some regions.
    #           When all regions support 3 fault domains, the default value should be changed to 3.
    def _default_fault_domain_count(global_azure_config)
      if global_azure_config.environment == ENVIRONMENT_AZURESTACK
        1
      else
        global_azure_config.use_managed_disks ? 2 : 3
      end
    end

    # @return [Array<Bosh::AzureCloud::LoadBalancerConfig>,nil]
    def _parse_load_balancer_config(vm_properties, global_azure_config)
      load_balancer_config = vm_properties[LOAD_BALANCER_KEY]

      return nil unless load_balancer_config

      cloud_error("Property '#{LOAD_BALANCER_KEY}' must be a String, Hash, or Array.") unless load_balancer_config.is_a?(String) || load_balancer_config.is_a?(Hash) || load_balancer_config.is_a?(Array)

      load_balancer_configs = load_balancer_config.is_a?(Array) ? load_balancer_config : [load_balancer_config]
      load_balancers = Array(load_balancer_configs).flat_map do |lbc|
        if lbc.is_a?(Hash)
          load_balancer_names = lbc[NAME_KEY]
          resource_group_name = lbc[RESOURCE_GROUP_NAME_KEY]
          backend_pool_name = lbc[BACKEND_POOL_NAME_KEY]
        else
          load_balancer_names = lbc
          resource_group_name = nil
          backend_pool_name = nil
        end
        String(load_balancer_names).split(',').map do |load_balancer_name|
          Bosh::AzureCloud::LoadBalancerConfig.new(
            resource_group_name || global_azure_config.resource_group_name,
            load_balancer_name,
            backend_pool_name
          )
        end
      end
      load_balancers.compact
    end

    # @return [Array<Bosh::AzureCloud::ApplicationGatewayConfig>,nil]
    def _parse_application_gateway_config(vm_properties)
      application_gateway_config = vm_properties[APPLICATION_GATEWAY_KEY]

      return nil unless application_gateway_config

      cloud_error("Property '#{APPLICATION_GATEWAY_KEY}' must be a String, Hash, or Array.") unless application_gateway_config.is_a?(String) || application_gateway_config.is_a?(Hash) || application_gateway_config.is_a?(Array)

      application_gateway_configs = application_gateway_config.is_a?(Array) ? application_gateway_config : [application_gateway_config]
      application_gateways = Array(application_gateway_configs).flat_map do |agwc|
        if agwc.is_a?(Hash)
          application_gateway_names = agwc[NAME_KEY]
          resource_group_name = agwc[RESOURCE_GROUP_NAME_KEY]
          backend_pool_name = agwc[BACKEND_POOL_NAME_KEY]
        else
          application_gateway_names = agwc
          resource_group_name = nil
          backend_pool_name = nil
        end
        String(application_gateway_names).split(',').map do |application_gateway_name|
          Bosh::AzureCloud::ApplicationGatewayConfig.new(
            # NOTE: It is OK for the resource_group_name to be `nil` here. The nil will be defaulted elsewhere (if needed). And leaving it nil makes the specs simpler.
            resource_group_name,
            application_gateway_name,
            backend_pool_name
          )
        end
      end
      application_gateways.compact
    end

    # @return [Bosh::AzureCloud::AvailabilitySetConfig]
    def _parse_availability_set_config(vm_properties, global_azure_config)
      if vm_properties[AVAILABILITY_SET_KEY].is_a?(Hash)
        platform_update_domain_count = vm_properties[AVAILABILITY_SET_KEY]['platform_update_domain_count'] || _default_update_domain_count(global_azure_config)
        platform_fault_domain_count = vm_properties[AVAILABILITY_SET_KEY]['platform_fault_domain_count'] || _default_fault_domain_count(global_azure_config)
        Bosh::AzureCloud::AvailabilitySetConfig.new(
          vm_properties[AVAILABILITY_SET_KEY][NAME_KEY],
          platform_update_domain_count,
          platform_fault_domain_count
        )
      else
        platform_update_domain_count = vm_properties['platform_update_domain_count'] || _default_update_domain_count(global_azure_config)
        platform_fault_domain_count = vm_properties['platform_fault_domain_count'] || _default_fault_domain_count(global_azure_config)
        Bosh::AzureCloud::AvailabilitySetConfig.new(
          vm_properties[AVAILABILITY_SET_KEY],
          platform_update_domain_count,
          platform_fault_domain_count
        )
      end
    end
  end
end
