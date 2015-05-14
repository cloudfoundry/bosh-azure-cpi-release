module Bosh::AzureCloud
  class AzureClient
    attr_accessor :blob_manager
    attr_accessor :disk_manager
    attr_accessor :stemcell_manager
    attr_accessor :vm_manager

    include Helpers

    def initialize(azure_properties, registry, logger)
      @logger = logger
      Azure::Core::Utility.initialize_external_logger(logger)
      Azure.configure do |config|
        config.subscription_id        = azure_properties['subscription_id']
        config.management_endpoint    = AZURE_ENVIRONMENTS[azure_properties['environment']]['managementEndpointUrl']
        config.storage_blob_host      = AZURE_ENVIRONMENTS[azure_properties['environment']]['managementEndpointUrl'].sub("//management.","//#{azure_properties['storage_account_name']}.blob.")
        config.storage_account_name   = azure_properties['storage_account_name']
        config.storage_access_key     = azure_properties['storage_access_key']
      end

      container_name = azure_properties['container_name'] || 'bosh'

      unless ENV.has_key?('HOME')
        user = 'vcap'
        user = azure_properties['ssh_user'] unless azure_properties['ssh_user'].nil?
        ENV['HOME'] = "/home/#{user}"
        @logger.info("Set HOME to #{ENV['HOME']}")
      end
      unless ENV.has_key?('PATH')
        ENV['PATH'] = "/usr/local/bin"
      else
        ENV['PATH'] = "#{ENV['PATH']}:/usr/local/bin" unless ENV['PATH'].include?("/usr/local/bin")
      end
      @logger.info("Set PATH to #{ENV['PATH']}")

      ENV['client_id'] = azure_properties['client_id']
      ENV['client_secret'] = azure_properties['client_secret']
      ENV['tenant_id'] = azure_properties['tenant_id']

      azure_cmd("azure config mode arm")
      azure_cmd("azure login -u #{azure_properties['client_id']} -p '#{azure_properties['client_secret']}' --tenant #{azure_properties['tenant_id']} --service-principal --quiet")

      if azure_properties['subscription_id']
        azure_cmd("azure account set #{azure_properties['subscription_id']}")
      end

      @blob_manager           = Bosh::AzureCloud::BlobManager.new
      @disk_manager           = Bosh::AzureCloud::DiskManager.new(container_name, @blob_manager)
      @stemcell_manager       = Bosh::AzureCloud::StemcellManager.new(@blob_manager)
      @vm_manager             = Bosh::AzureCloud::VMManager.new(azure_properties['storage_account_name'], registry, @disk_manager)
    end
  end
end