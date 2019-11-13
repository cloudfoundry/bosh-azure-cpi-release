# frozen_string_literal: true

module Bosh::AzureCloud
  class StorageAccountManager
    include Helpers

    attr_reader :use_default_account_for_cleaning
    def initialize(azure_config, blob_manager, azure_client)
      @azure_config = azure_config
      @blob_manager = blob_manager
      @azure_client = azure_client
      @use_managed_disks = @azure_config.use_managed_disks
      @logger = Bosh::Clouds::Config.logger

      @default_storage_account_name = nil
      @default_storage_account = nil
      @use_default_account_for_cleaning = @azure_config.use_default_account_for_cleaning
    end

    def generate_storage_account_name
      available = false
      until available
        # The length of the random storage account name is 24, twice of 12.
        storage_account_name = SecureRandom.hex(12).to_s
        @logger.debug('generate_storage_account_name - generating a new storage account name')
        result = @azure_client.check_storage_account_name_availability(storage_account_name)
        available = result[:available]
        @logger.debug('generate_storage_account_name - The generated storage account name is not available') unless available
      end
      @logger.debug("generate_storage_account_name - The storage account name '#{storage_account_name}' is available")
      storage_account_name
    end

    # Create storage account. If the storage account exists, return the storage account directly.
    # @param [String]  name                        - Name of storage account.
    # @param [Hash]    tags                        - Tags for the storage account.
    # @param [String]  sku                         - Sku name of storage account. Options: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    # @param [String]  kind                        - Kind of storage account. Options: Storage, StorageV2
    # @param [String]  location                    - Location where the storage account will be created.
    # @param [Array]   containers                  - Container that will be created in the storage account
    # @param [Boolean] is_default_storage_account  - The storage account will be created as the default storage account
    # @return [Hash]
    def get_or_create_storage_account(name, tags, sku, kind, location, containers, is_default_storage_account)
      @logger.debug("get_or_create_storage_account(#{name}, #{tags}, #{sku}, #{kind}, #{location}, #{containers}, #{is_default_storage_account})")
      storage_account = nil
      flock("#{CPI_LOCK_PREFIX_STORAGE_ACCOUNT}-#{name}", File::LOCK_EX) do
        storage_account = find_storage_account_by_name(name) # make sure the storage account is not yet created by other process
        if storage_account.nil?
          @logger.debug("Cannot find any storage account with name '#{name}', creating a new one...")
          result = @azure_client.check_storage_account_name_availability(name)
          @logger.debug("get_or_create_storage_account - The result of check_storage_account_name_availability is #{result}")
          unless result[:available]
            if result[:reason] == 'AccountNameInvalid'
              raise "The storage account name '#{name}' is invalid. Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only. #{result[:message]}"
            else
              # AlreadyExists
              raise "The storage account with the name '#{name}' is not available. Error: #{result[:message]}"
            end
          end

          raise 'Require name to create a new storage account' if name.nil?
          raise "Require type to create a new storage account. If you specify 'storage_account_name' in resource pool to use & create a new storage account, please also provide 'storage_account_type'" if sku.nil?
          raise 'Require location to create a new storage account' if location.nil?

          @logger.debug("Creating storage account '#{name}' with the tags '#{tags}' in the location '#{location}'")
          @azure_client.create_storage_account(name, location, sku, kind, tags)
          storage_account = find_storage_account_by_name(name)
          cloud_error("Storage account '#{name}' is not created.") if storage_account.nil?
        end
      end
      storage_account
    end

    # Create storage account when name is not provided, the storage account would be identified by its tags and location
    # @param [Hash]    tags                        - Tags for the storage account.
    # @param [String]  sku                         - Sku name of storage account. Options: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    # @param [String]  kind                        - Kind of storage account. Options: Storage, StorageV2
    # @param [String]  location                    - Location where the storage account will be created.
    # @param [Array]   containers                  - Container that will be created in the storage account
    # @param [Boolean] is_default_storage_account  - The storage account will be created as the default storage account
    # @return [Hash]
    def get_or_create_storage_account_by_tags(tags, sku, kind, location, containers, is_default_storage_account)
      @logger.debug("get_or_create_storage_account_by_tags(#{tags}, #{sku}, #{kind}, #{location}, #{containers}, #{is_default_storage_account})")
      storage_account = nil
      lock_file = "#{CPI_LOCK_PREFIX_STORAGE_ACCOUNT}-#{location}-#{Digest::MD5.hexdigest(tags.to_s)}"
      flock(lock_file, File::LOCK_EX) do
        storage_account = find_storage_account_by_tags(tags, location) # make sure the storage account is not yet created by other process
        if storage_account.nil?
          @logger.debug("Cannot find any storage account in the location '#{location}' with tags '#{tags}', creating a new one...")
          name = generate_storage_account_name
          storage_account = get_or_create_storage_account(name, tags, sku, kind, location, containers, is_default_storage_account)
        end
      end
      cloud_error("Storage account for tags '#{tags}' is not created.") if storage_account.nil?
      storage_account
    end

    # Find storage account
    # @param [String] name - storage account name.
    # @return [Hash]
    def find_storage_account_by_name(name)
      @logger.debug("find_storage_account_by_name(#{name})")
      storage_account = @azure_client.get_storage_account_by_name(name)
      @logger.debug("Found storage account: '#{storage_account[:name]}'") unless storage_account.nil?
      storage_account
    end

    # Find storage account by tags, assume that in the default resource group there is only one storage account with tags for each location.
    # @param [Hash] tags                   - tags.
    # @param [String] location             - location
    # @return [Hash]
    def find_storage_account_by_tags(tags, location)
      @logger.debug("find_storage_account_by_tags(#{tags}, #{location})")
      storage_accounts = @azure_client.list_storage_accounts
      storage_account = storage_accounts.find do |s|
        (s[:location] == location) && (tags.to_a - s[:tags].to_a).empty?
      end
      @logger.debug("Found storage account: '#{storage_account[:name]}'") unless storage_account.nil?
      storage_account
    end

    def default_storage_account_name
      return @default_storage_account_name unless @default_storage_account_name.nil?

      unless @azure_config.storage_account_name.nil?
        @default_storage_account_name = @azure_config.storage_account_name
        return @default_storage_account_name
      end

      @default_storage_account_name = default_storage_account[:name]
    end

    def default_storage_account
      return @default_storage_account unless @default_storage_account.nil?

      storage_account_name = @azure_config.storage_account_name
      unless storage_account_name.nil?
        @logger.debug("The default storage account in global settings is '#{storage_account_name}'")
        @default_storage_account = @azure_client.get_storage_account_by_name(storage_account_name)
        cloud_error("The default storage account '#{storage_account_name}' is specified in Global Configuration, but it does not exist.") if @default_storage_account.nil?
        @azure_client.update_tags_of_storage_account(storage_account_name, STEMCELL_STORAGE_ACCOUNT_TAGS) if @use_managed_disks && !is_stemcell_storage_account?(@default_storage_account[:tags])
        return @default_storage_account
      end
      @logger.debug("The default storage account is not specified in global settings.")

      storage_account_name = get_storage_account_name_from_cache
      unless storage_account_name.empty?
        @logger.debug("Choose the default storage account from cache: '#{storage_account_name}'")
        storage_account = @azure_client.get_storage_account_by_name(storage_account_name)
        unless storage_account.nil?
          @default_storage_account = storage_account
          return @default_storage_account
        end
        remove_storage_account_name_cache
        @logger.debug("The storage account '#{storage_account_name}' from cache does not exist.")
      end
      @logger.debug("The default storage account is not specified in cache.")

      storage_accounts = @azure_client.list_storage_accounts
      location = @azure_client.get_resource_group(@azure_config.resource_group_name)[:location]
      @logger.debug("Will look for an existing storage account with the tags '#{STEMCELL_STORAGE_ACCOUNT_TAGS}' in the location '#{location}'")
      storage_account = storage_accounts.find do |s|
        s[:location] == location && is_stemcell_storage_account?(s[:tags])
      end
      unless storage_account.nil?
        storage_account_name = storage_account[:name]
        @logger.debug("Choose '#{storage_account_name}' as the default storage account")
        @default_storage_account = storage_account
        @azure_client.update_tags_of_storage_account(storage_account_name, STEMCELL_STORAGE_ACCOUNT_TAGS) if @use_managed_disks && !is_stemcell_storage_account?(@default_storage_account[:tags])
        set_storage_account_name_to_cache(storage_account_name)
        return @default_storage_account
      end

      @logger.debug("Can't find a storage account with the tags '#{STEMCELL_STORAGE_ACCOUNT_TAGS}'")
      @logger.debug("Will look for the old storage account (with the table '#{STEMCELL_TABLE}') which stores all uploaded stemcells")
      storage_account = storage_accounts.find do |s|
        s[:sku_tier].casecmp('standard').zero? && _has_stemcell_table?(s[:name])
      end

      unless storage_account.nil?
        storage_account_name = storage_account[:name]
        if storage_account[:location] == location
          @logger.debug("Use an exisiting storage account '#{storage_account_name}' as the default storage account")
          @logger.debug("Set the tags '#{STEMCELL_STORAGE_ACCOUNT_TAGS}' for the storage account '#{storage_account_name}'")
          @azure_client.update_tags_of_storage_account(storage_account_name, STEMCELL_STORAGE_ACCOUNT_TAGS)
          @default_storage_account = storage_account
          return @default_storage_account
        else
          error_msg = "The existing default storage account '#{storage_account_name}' has a different location other than the resource group location.\n"
          error_msg += "For migration, please create a new storage account in the resource group location '#{location}' as the default storage account,\n"
          error_msg += "and copy the container '#{STEMCELL_CONTAINER}' and the tabel '#{STEMCELL_TABLE}' from the old one to the new one."
          cloud_error(error_msg)
        end
      end

      storage_account = get_or_create_storage_account_by_tags(
        STEMCELL_STORAGE_ACCOUNT_TAGS,
        STORAGE_ACCOUNT_TYPE_STANDARD_LRS,
        STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1,
        location,
        [DISK_CONTAINER, STEMCELL_CONTAINER],
        true
      )
      @logger.debug("The default storage account is '#{storage_account[:name]}'")
      @default_storage_account = storage_account
    end

    def get_or_create_diagnostics_storage_account(location)
      @logger.debug("get_or_create_diagnostics_storage_account(#{location})")
      get_or_create_storage_account_by_tags(
        DIAGNOSTICS_STORAGE_ACCOUNT_TAGS,
        STORAGE_ACCOUNT_TYPE_STANDARD_LRS,
        STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1,
        location,
        [],
        false
      )
    end

    private

    # If the storage account has the table #{STEMCELL_TABLE}, then it stores all uploaded stemcells
    def _has_stemcell_table?(name)
      storage_account = @azure_client.get_storage_account_by_name(name)
      storage_account[:key] = @azure_client.get_storage_account_keys_by_name(name)[0]
      azure_storage_client = initialize_azure_storage_client(storage_account, @azure_config)
      table_service_client = azure_storage_client.table_client
      table_service_client.with_filter(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter.new)
      table_service_client.with_filter(Azure::Core::Http::DebugFilter.new) if is_debug_mode(@azure_config)
      begin
        options = merge_storage_common_options
        @logger.info("_has_stemcell_table?: Calling get_table(#{STEMCELL_TABLE}, #{options})")
        table_service_client.get_table(STEMCELL_TABLE, options)
        true
      rescue StandardError => e
        cloud_error("_has_stemcell_table?: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?('(404)')
        false
      end
    end
  end
end
