# frozen_string_literal: true

module Bosh::AzureCloud
  class LoadBalancerConfig
    attr_reader :name, :resource_group_name
    def initialize(resource_group_name, name)
      @resource_group_name = resource_group_name
      @name = name
    end

    def to_s
      "name: #{@name}, resource_group_name: #{@resource_group_name}"
    end
  end

  class AvailabilitySetConfig
    attr_reader :name
    attr_reader :platform_update_domain_count, :platform_fault_domain_count
    def initialize(name, platform_update_domain_count, platform_fault_domain_count)
      @name = name
      @platform_update_domain_count = platform_update_domain_count
      @platform_fault_domain_count = platform_fault_domain_count
    end

    def to_s
      "name: #{@name}, platform_update_domain_count: #{@platform_update_domain_count} platform_fault_domain_count: #{@platform_fault_domain_count}"
    end
  end

  class AzureStackConfig
    attr_reader :domain, :authentication, :resource, :endpoint_prefix
    attr_writer :authentication
    def initialize(azure_stack_config_hash)
      @domain = azure_stack_config_hash['domain']
      @authentication = azure_stack_config_hash['authentication']
      @resource = azure_stack_config_hash['resource']
      @endpoint_prefix = azure_stack_config_hash['endpoint_prefix']
    end
  end

  class ConfigDisk
    attr_reader :enabled
    def initialize(config_disk_config_hash)
      @enabled = config_disk_config_hash['enabled']
    end
  end

  class AzureConfig
    include Helpers
    attr_reader :environment, :subscription_id, :location, :resource_group_name
    attr_reader :azure_stack
    attr_reader :credentials_source, :tenant_id, :client_id, :client_secret, :default_managed_identity
    attr_reader :use_managed_disks, :storage_account_name
    attr_reader :default_security_group
    attr_reader :enable_vm_boot_diagnostics, :is_debug_mode, :keep_failed_vms
    attr_reader :enable_telemetry, :isv_tracking_guid
    attr_reader :pip_idle_timeout_in_minutes
    attr_reader :parallel_upload_thread_num
    attr_reader :ssh_user, :ssh_public_key
    attr_reader :config_disk

    attr_writer :storage_account_name

    def initialize(azure_config_hash)
      @environment = azure_config_hash['environment']
      @environment == ENVIRONMENT_AZURESTACK && !azure_config_hash['azure_stack'].nil? && @azure_stack = AzureStackConfig.new(azure_config_hash['azure_stack'])
      @subscription_id = azure_config_hash['subscription_id']
      @location = azure_config_hash['location']
      @resource_group_name = azure_config_hash['resource_group_name']

      # Identity
      @credentials_source = azure_config_hash['credentials_source']
      @tenant_id = azure_config_hash['tenant_id']
      @client_id = azure_config_hash['client_id']
      @client_secret = azure_config_hash['client_secret']
      @default_managed_identity = Bosh::AzureCloud::ManagedIdentity.new(azure_config_hash['default_managed_identity']) unless azure_config_hash['default_managed_identity'].nil?

      @use_managed_disks = azure_config_hash['use_managed_disks']
      @storage_account_name = azure_config_hash['storage_account_name']

      @default_security_group = Bosh::AzureCloud::SecurityGroup.parse_security_group(
        azure_config_hash['default_security_group']
      )

      # Troubleshooting
      @enable_vm_boot_diagnostics = azure_config_hash['enable_vm_boot_diagnostics']
      @is_debug_mode = false
      @is_debug_mode = azure_config_hash['debug_mode'] unless azure_config_hash['debug_mode'].nil?
      @keep_failed_vms = azure_config_hash['keep_failed_vms']

      # Telemetry
      @enable_telemetry = azure_config_hash.fetch('enable_telemetry', false)
      @isv_tracking_guid = azure_config_hash.fetch('isv_tracking_guid', DEFAULT_ISV_TRACKING_GUID)

      @pip_idle_timeout_in_minutes = azure_config_hash.fetch('pip_idle_timeout_in_minutes', 4)

      @parallel_upload_thread_num = 16
      @parallel_upload_thread_num = azure_config_hash['parallel_upload_thread_num'].to_i unless azure_config_hash['parallel_upload_thread_num'].nil?

      @ssh_user = azure_config_hash['ssh_user']
      @ssh_public_key = azure_config_hash['ssh_public_key']

      @config_disk = ConfigDisk.new(azure_config_hash.fetch('config_disk', 'enabled' => false))
    end

    def managed_identity_enabled?
      @credentials_source == CREDENTIALS_SOURCE_MANAGED_IDENTITY
    end
  end

  class RegistryConfig
    attr_reader :endpoint, :user, :password

    def initialize(registry_config_hash)
      @config = registry_config_hash

      @endpoint = @config['endpoint']
      @user = @config['user']
      @password = @config['password']
    end
  end

  class AgentConfig
    def initialize(agent_config_hash)
      @config = agent_config_hash
    end

    def to_h
      @config
    end
  end

  class Config
    attr_reader :azure, :registry, :agent
    def initialize(config_hash)
      @config = config_hash
      @azure = AzureConfig.new(config_hash['azure'] || {})
      @registry = RegistryConfig.new(config_hash['registry'] || {})
      @agent = AgentConfig.new(config_hash['agent'] || {})
    end
  end
end
