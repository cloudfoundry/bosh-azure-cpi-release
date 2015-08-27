module Bosh::AzureCloud
  class AzureClient
    attr_accessor :blob_manager
    attr_accessor :disk_manager
    attr_accessor :stemcell_manager
    attr_accessor :vm_manager

    include Helpers

    def initialize(azure_properties, registry_endpoint)
      Azure.configure do |config|
        config.subscription_id      = azure_properties['subscription_id']
        config.management_endpoint  = AZURE_ENVIRONMENTS[azure_properties['environment']]['managementEndpointUrl']
        config.storage_account_name = azure_properties['storage_account_name']
        config.storage_access_key   = azure_properties['storage_access_key']
      end

      parallel_upload_thread_num = 16
      parallel_upload_thread_num = azure_properties['parallel_upload_thread_num'].to_i unless azure_properties['parallel_upload_thread_num'].nil?
      @blob_manager     = Bosh::AzureCloud::BlobManager.new(parallel_upload_thread_num)
      @disk_manager     = Bosh::AzureCloud::DiskManager.new(@blob_manager)
      @stemcell_manager = Bosh::AzureCloud::StemcellManager.new(@blob_manager)
      @vm_manager       = Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, @disk_manager)
    end
  end
end