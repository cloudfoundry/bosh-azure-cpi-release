module Bosh::AzureCloud
  class StorageAccountManager
    include Helpers

    def initialize(azure_properties, blob_manager, disk_manager, azure_client2)
      @azure_properties = azure_properties
      @blob_manager  = blob_manager
      @disk_manager  = disk_manager
      @azure_client2 = azure_client2
      @use_managed_disks = @azure_properties['use_managed_disks']
      @logger = Bosh::Clouds::Config.logger

      @default_storage_account_name = nil
      @default_storage_account = nil
    end

    def generate_storage_account_name()
      available = false
      until available do
        # The length of the random storage account name is 24, twice of 12.
        storage_account_name = "#{SecureRandom.hex(12)}"
        @logger.debug("generate_storage_account_name - generating a new storage account name")
        result = @azure_client2.check_storage_account_name_availability(storage_account_name)
        available = result[:available]
        @logger.debug("generate_storage_account_name - The generated storage account name is not available") unless available
      end
      @logger.debug("generate_storage_account_name - The storage account name `#{storage_account_name}' is available")
      storage_account_name
    end

    # Create storage account. If the storage account exists, return the storage account directly.
    # @param [String]  name                        - Name of storage account.
    # @param [Hash]    tags                        - Tags for the storage account.
    # @param [String]  type                        - Type of storage account. Options: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    # @param [String]  location                    - Location where the storage account will be created.
    # @param [Array]   containers                  - Container that will be created in the storage account
    # @param [Boolean] is_default_storage_account  - The storage account will be created as the default storage account
    # @return [Hash]
    def get_or_create_storage_account(name, tags, type, location, containers, is_default_storage_account)
      @logger.debug("get_or_create_storage_account(#{name}, #{tags}, #{type}, #{location}, #{containers}, #{is_default_storage_account})")
      lock_file = "#{CPI_LOCK_CREATE_STORAGE_ACCOUNT}-#{name}"
      mutex = FileMutex.new(lock_file, @logger, CPI_LOCK_CREATE_STORAGE_ACCOUNT_TIMEOUT)
      begin
        if mutex.lock
          storage_account = find_storage_account_by_name(name) # make sure the storage account is not yet created by other process
          if storage_account.nil?
            @logger.debug("Cannot find any storage account with name `#{name}', creating a new one...")
            result = @azure_client2.check_storage_account_name_availability(name)
            @logger.debug("get_or_create_storage_account - The result of check_storage_account_name_availability is #{result}")
            unless result[:available]
              if result[:reason] == 'AccountNameInvalid'
                raise "The storage account name `#{name}' is invalid. Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only. #{result[:message]}"
              else
                # AlreadyExists
                raise "The storage account with the name `#{name}' is not available. Error: #{result[:message]}"
              end
            end

            begin
              raise "Require name to create a new storage account" if name.nil?
              raise "Require type to create a new storage account. If you specify `storage_account_name' in resource pool to use & create a new storage account, please also provide `storage_account_type'" if type.nil?
              raise "Require location to create a new storage account" if location.nil?

              @logger.debug("Creating storage account `#{name}' with the tags `#{tags}' in the location `#{location}'")
              created = @azure_client2.create_storage_account(name, location, type, tags)
              @blob_manager.prepare_containers(name, containers, is_default_storage_account) unless containers.empty?
            rescue => e
              error_msg = "get_or_create_storage_account - "
              if created
                error_msg += "The storage account `#{name}' is created successfully.\n"
                error_msg += "But it failed to prepare the containers `#{containers}'.\n"
                error_msg += "You need to manually create them if they don't exist.\n"
                error_msg += "And set the public access level of the container `#{STEMCELL_CONTAINER}' to `#{PUBLIC_ACCESS_LEVEL_BLOB}'.\n" if is_default_storage_account
                # TODO: clean up the storage account if it failed to create containers.
              end
              error_msg += "Error: #{e.inspect}\n#{e.backtrace.join("\n")}"
              raise error_msg
            end
            storage_account = find_storage_account_by_name(name)
          end
          mutex.unlock
        else
          mutex.wait
          storage_account = find_storage_account_by_name(name)
        end
      rescue => e
        mark_deleting_locks
        cloud_error("Failed to create storage account in location `#{location}' with name `#{name}' and tags `#{tags}'. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
      end
      cloud_error("Storage account `#{name}' is not created.") if storage_account.nil?
      storage_account
    end

    # Create storage account when name is not provided, the storage account would be identified by its tags and location
    # @param [Hash]    tags                        - Tags for the storage account.
    # @param [String]  type                        - Type of storage account. Options: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    # @param [String]  location                    - Location where the storage account will be created.
    # @param [Array]   containers                  - Container that will be created in the storage account
    # @param [Boolean] is_default_storage_account  - The storage account will be created as the default storage account
    # @return [Hash]
    def get_or_create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
      @logger.debug("get_or_create_storage_account_by_tags(#{tags}, #{type}, #{location}, #{containers}, #{is_default_storage_account})")
      lock_file = "#{CPI_LOCK_CREATE_STORAGE_ACCOUNT}-#{location}-#{Digest::MD5.hexdigest(tags.to_s)}"
      mutex = FileMutex.new(lock_file, @logger, CPI_LOCK_CREATE_STORAGE_ACCOUNT_TIMEOUT)
      begin
        if mutex.lock
          storage_account = find_storage_account_by_tags(tags, location) # make sure the storage account is not yet created by other process
          if storage_account.nil?
            @logger.debug("Cannot find any storage account in the location `#{location}' with tags `#{tags}', creating a new one...")
            name = generate_storage_account_name()
            storage_account = get_or_create_storage_account(name, tags, type, location, containers, is_default_storage_account)
          end
          mutex.unlock
        else
          mutex.wait
          storage_account = find_storage_account_by_tags(tags, location)
        end
      rescue => e
        mark_deleting_locks
        cloud_error("Failed to create storage account in location `#{location}' with tags `#{tags}'. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
      end
      cloud_error("Storage account for tags `#{tags}' is not created.") if storage_account.nil?
      storage_account
    end


    # Find storage account
    # @param [String] name - storage account name.
    # @return [Hash]
    def find_storage_account_by_name(name)
      @logger.debug("find_storage_account_by_name(#{name})")
      storage_account = @azure_client2.get_storage_account_by_name(name)
      @logger.debug("Found storage account: `#{storage_account[:name]}'") unless storage_account.nil?
      storage_account
    end

    # Find storage account by tags, assume that in the default resource group there is only one storage account with tags for each location.
    # @param [Hash] tags                   - tags.
    # @param [String] location             - location
    # @return [Hash]
    def find_storage_account_by_tags(tags, location)
      @logger.debug("find_storage_account_by_tags(#{tags}, #{location})")
      storage_accounts = @azure_client2.list_storage_accounts()
      storage_account = storage_accounts.find{ |s|
        (s[:location] == location) && (tags.to_a - s[:tags].to_a).empty?
      }
      @logger.debug("Found storage account: `#{storage_account[:name]}'") unless storage_account.nil?
      storage_account
    end

    def get_storage_account_from_resource_pool(resource_pool, location)
      @logger.debug("get_storage_account_from_resource_pool(#{resource_pool}, #{location})")

      # If storage_account_name is not specified in resource_pool, use the default storage account in global configurations
      storage_account_name = default_storage_account_name
      unless resource_pool['storage_account_name'].nil?
        if resource_pool['storage_account_name'].include?('*')
          ret = resource_pool['storage_account_name'].match('^\*{1}[a-z0-9]+\*{1}$')
          cloud_error("get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid. It should be '*keyword*' (keyword only contains numbers and lower-case letters) if it is a pattern.") if ret.nil?

          # Users could use *xxx* as the pattern
          # Users could specify the maximum disk numbers storage_account_max_disk_number in one storage account. Default is 30.
          # CPI uses the pattern to filter all storage accounts under the default resource group and
          # then randomly select an available storage account in which the disk numbers under the container `bosh'
          # is not more than the limitation.
          pattern = resource_pool['storage_account_name']
          storage_account_max_disk_number = resource_pool.fetch('storage_account_max_disk_number', 30)
          @logger.debug("get_storage_account_from_resource_pool - Picking one available storage account by pattern `#{pattern}', max disk number `#{storage_account_max_disk_number}'")

          # Remove * in the pattern
          pattern = pattern[1..-2]
          storage_accounts = @azure_client2.list_storage_accounts().select{ |s| s[:name] =~ /^.*#{pattern}.*$/ }
          @logger.debug("get_storage_account_from_resource_pool - Pick all storage accounts by pattern:\n#{storage_accounts.inspect}")

          result = []
          # Randomaly pick one storage account
          storage_accounts.shuffle!
          storage_accounts.each do |storage_account|
            disks = @disk_manager.list_disks(storage_account[:name])
            if disks.size <= storage_account_max_disk_number
              @logger.debug("get_storage_account_from_resource_pool - Pick the available storage account `#{storage_account[:name]}', current disk numbers: `#{disks.size}'")
              return storage_account
            else
              result << {
                :name => storage_account[:name],
                :disk_count => disks.size
              }
            end
          end

          cloud_error("get_storage_account_from_resource_pool - Cannot find an available storage account.\n#{result.inspect}")
        else
          storage_account_name = resource_pool['storage_account_name']
          storage_account_type = resource_pool['storage_account_type']
          # Create the storage account automatically if the storage account in resource_pool does not exist
          storage_account = get_or_create_storage_account(storage_account_name, {}, storage_account_type, location, [DISK_CONTAINER, STEMCELL_CONTAINER], false)
        end
      end

      @logger.debug("get_storage_account_from_resource_pool: use the storage account `#{storage_account_name}'")
      storage_account = @azure_client2.get_storage_account_by_name(storage_account_name) if storage_account.nil?
      storage_account
    end

    def default_storage_account_name()
      return @default_storage_account_name unless @default_storage_account_name.nil?

      if @azure_properties.has_key?('storage_account_name')
        @default_storage_account_name = @azure_properties['storage_account_name']
        return @default_storage_account_name
      end

      @default_storage_account_name = default_storage_account[:name]
    end

    def default_storage_account()
      return @default_storage_account unless @default_storage_account.nil?

      storage_account_name = nil
      if @azure_properties.has_key?('storage_account_name')
        storage_account_name = @azure_properties['storage_account_name']
        @logger.debug("The default storage account is `#{storage_account_name}'")
        @default_storage_account = @azure_client2.get_storage_account_by_name(storage_account_name)
        cloud_error("The default storage account `#{storage_account_name}' is specified in Global Configuration, but it does not exist.") if @default_storage_account.nil?
        if @use_managed_disks && !is_stemcell_storage_account?(@default_storage_account[:tags])
          @azure_client2.update_tags_of_storage_account(storage_account_name, STEMCELL_STORAGE_ACCOUNT_TAGS)
        end
        return @default_storage_account
      end

      @logger.debug("The default storage account is not specified in global settings.")
      storage_accounts = @azure_client2.list_storage_accounts()
      location = @azure_client2.get_resource_group(@azure_properties['resource_group_name'])[:location]
      @logger.debug("Will look for an existing storage account with the tags `#{STEMCELL_STORAGE_ACCOUNT_TAGS}' in the location `#{location}'")
      storage_account = storage_accounts.find{ |s|
        s[:location] == location && is_stemcell_storage_account?(s[:tags])
      }
      unless storage_account.nil?
        @logger.debug("The default storage account is `#{storage_account[:name]}'")
        @default_storage_account = storage_account
        return @default_storage_account
      end

      @logger.debug("Can't find a storage account with the tags `#{STEMCELL_STORAGE_ACCOUNT_TAGS}'")
      @logger.debug("Will look for the old storage account (with the table `#{STEMCELL_TABLE}') which stores all uploaded stemcells")
      storage_account = storage_accounts.find{ |s|
        s[:account_type].downcase.start_with?('standard') && has_stemcell_table?(s[:name])
      }

      unless storage_account.nil?
        storage_account_name = storage_account[:name]
        if storage_account[:location] == location
          @logger.debug("Use an exisiting storage account `#{storage_account_name}' as the default storage account")
          @logger.debug("Set the tags `#{STEMCELL_STORAGE_ACCOUNT_TAGS}' for the storage account `#{storage_account_name}'")
          @azure_client2.update_tags_of_storage_account(storage_account_name, STEMCELL_STORAGE_ACCOUNT_TAGS)
          @default_storage_account = storage_account
          return @default_storage_account
        else
          error_msg = "The existing default storage account `#{storage_account_name}' has a different location other than the resource group location.\n"
          error_msg += "For migration, please create a new storage account in the resource group location `#{location}' as the default storage account,\n"
          error_msg += "and copy the container `#{STEMCELL_CONTAINER}' and the tabel `#{STEMCELL_TABLE}' from the old one to the new one."
          cloud_error(error_msg)
        end
      end

      storage_account = get_or_create_storage_account_by_tags(STEMCELL_STORAGE_ACCOUNT_TAGS, STORAGE_ACCOUNT_TYPE_STANDARD_LRS, location, [DISK_CONTAINER, STEMCELL_CONTAINER], true)
      @logger.debug("The default storage account is `#{storage_account[:name]}'")
      @default_storage_account = storage_account
    end

    def get_or_create_diagnostics_storage_account(location)
      @logger.debug("get_or_create_diagnostics_storage_account(#{location})")
      get_or_create_storage_account_by_tags(DIAGNOSTICS_STORAGE_ACCOUNT_TAGS, STORAGE_ACCOUNT_TYPE_STANDARD_LRS, location, [], false)
    end

    private

    # If the storage account has the table #{STEMCELL_TABLE}, then it stores all uploaded stemcells
    def has_stemcell_table?(name)
      storage_account = @azure_client2.get_storage_account_by_name(name)
      storage_account[:key] = @azure_client2.get_storage_account_keys_by_name(name)[0]
      azure_storage_client = initialize_azure_storage_client(storage_account, @azure_properties)
      table_service_client = azure_storage_client.table_client
      table_service_client.with_filter(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter.new)
      table_service_client.with_filter(Azure::Core::Http::DebugFilter.new) if is_debug_mode(@azure_properties)
      begin
        options = merge_storage_common_options()
        @logger.info("has_stemcell_table?: Calling get_table(#{STEMCELL_TABLE}, #{options})")
        table_service_client.get_table(STEMCELL_TABLE, options)
        true
      rescue => e
        cloud_error("has_stemcell_table?: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?("(404)")
        false
      end
    end
  end
end
