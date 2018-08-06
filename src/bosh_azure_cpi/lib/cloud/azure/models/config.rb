# frozen_string_literal: true

module Bosh::AzureCloud
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

  class AzureConfig
    include Helpers
    attr_reader :use_managed_disks, :enable_telemetry
    attr_reader :environment, :subscription_id, :location, :resource_group_name
    attr_reader :is_debug_mode
    attr_reader :azure_stack
    attr_reader :tenant_id, :client_id, :client_secret
    attr_reader :parallel_upload_thread_num
    attr_reader :ssh_user, :ssh_public_key, :enable_vm_boot_diagnostics, :default_security_group, :keep_failed_vms
    attr_reader :pip_idle_timeout_in_minutes
    attr_reader :storage_account_name
    attr_reader :isv_tracking_guid

    attr_writer :storage_account_name

    def initialize(azure_config_hash)
      @use_managed_disks = azure_config_hash['use_managed_disks']
      @enable_telemetry = azure_config_hash.fetch('enable_telemetry', false)
      @environment = azure_config_hash['environment']
      @subscription_id = azure_config_hash['subscription_id']
      @location = azure_config_hash['location']
      @resource_group_name = azure_config_hash['resource_group_name']
      @storage_account_name = azure_config_hash['storage_account_name']

      @keep_failed_vms = azure_config_hash['keep_failed_vms']
      @enable_vm_boot_diagnostics = azure_config_hash['enable_vm_boot_diagnostics']
      @ssh_user = azure_config_hash['ssh_user']
      @ssh_public_key = azure_config_hash['ssh_public_key']
      @default_security_group = azure_config_hash['default_security_group']

      @pip_idle_timeout_in_minutes = azure_config_hash.fetch('pip_idle_timeout_in_minutes', 4)

      @parallel_upload_thread_num = 16
      @parallel_upload_thread_num = azure_config_hash['parallel_upload_thread_num'].to_i unless azure_config_hash['parallel_upload_thread_num'].nil?

      @is_debug_mode = false
      @is_debug_mode = azure_config_hash['debug_mode'] unless azure_config_hash['debug_mode'].nil?

      @tenant_id = azure_config_hash['tenant_id']
      @client_id = azure_config_hash['client_id']
      @client_secret = azure_config_hash['client_secret']

      @environment == ENVIRONMENT_AZURESTACK && !azure_config_hash['azure_stack'].nil? && @azure_stack = AzureStackConfig.new(azure_config_hash['azure_stack'])

      @isv_tracking_guid = azure_config_hash.fetch('isv_tracking_guid', DEFAULT_ISV_TRACKING_GUID)
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
