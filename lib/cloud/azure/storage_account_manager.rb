module Bosh::AzureCloud
  class StorageAccountManager
    
    attr_accessor :logger

    def initialize(storage_account_name)
      @storage_service = Azure::StorageManagement::StorageManagementService.new
      @storage_account_name = storage_account_name

      @logger = Bosh::Clouds::Config.logger
    end
    
    def get_storage_account_name
      @storage_account_name
    end
    
    def get_storage_affinity_group
      get_storage_properties.affinity_group
    end
    
    def get_storage_blob_endpoint
      blob_endpoint = ""
      get_storage_properties.endpoints.each do |endpoint|
        if endpoint.include? "blob"
          blob_endpoint = endpoint
          break
        end
      end
      
      blob_endpoint
    end
    
    private
    
    def get_storage_properties
      @storage_service.get_storage_account_properties(@storage_account_name)
    end
  end
end