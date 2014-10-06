

module Bosh::AzureCloud
  class StorageAccountManager

    def initialize(storage_client, storage_account_name)
      @storage_client = storage_client
      @storage_account_name = storage_account_name
    end

    def create
      begin
        @storage_client.create_storage_account(@storage_account_name, {
            :label => 'bosh-managed-storage',
            # TODO: Support more than East US
            :location => 'East US' # Specify East US to avoid affinity group requirement.
        }) unless exist?
      rescue ConflictError => e
        # TODO: Need to return a bosh error so deployment doesn't continue.
        puts "Storage account name '#{@storage_account_name}' is already taken in another account. Remember,
              the namespace for storage accounts is shared between all azure users"
      end

      @storage_account_name
    end

    def exist?
      @storage_client.get_storage_account(@storage_account_name)
    end
  end
end