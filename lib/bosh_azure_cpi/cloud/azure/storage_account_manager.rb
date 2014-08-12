

module Bosh::AzureCloud
  class StorageAccountManager

    def initialize(storage_client, storage_account_name)
      @storage_client = storage_client
      @storage_account_name = storage_account_name
    end

    def create
      @storage_client.create_storage_account(@storage_account_name, {
          :label => 'bosh-managed-storage',
          # TODO: Support more than East US
          :location => 'East US' # Specify East US to avoid affinity group requirement.
      }) unless exist?
    end

    def exist?
      @storage_client.get_storage_account(@storage_account_name)
    end
  end
end