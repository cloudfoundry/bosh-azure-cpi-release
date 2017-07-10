module Bosh::AzureCloud
  class StemcellManager2 < StemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, table_manager, storage_account_manager, azure_client2)
      super(blob_manager, table_manager, storage_account_manager)
      @azure_client2 = azure_client2
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")

      user_images = @azure_client2.list_user_images().select{ |item| item[:name] =~ /^#{name}/ }
      user_images.each do |user_image|
        user_image_name = user_image[:name]
        @logger.info("Delete user image `#{user_image_name}'")
        @azure_client2.delete_user_image(user_image_name)
      end

      # Delete all stemcells with the given stemcell name in all storage accounts
      storage_accounts = @azure_client2.list_storage_accounts()
      storage_accounts.each do |storage_account|
        storage_account_name = storage_account[:name]
        @logger.info("Delete stemcell `#{name}' in the storage `#{storage_account_name}'")
        @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(storage_account_name, name)
      end

      # Delete all records whose PartitionKey is the given stemcell name
      if @table_manager.has_table?(STEMCELL_TABLE)
        options = {
          :filter => "PartitionKey eq '#{name}'"
        }
        entities = @table_manager.query_entities(STEMCELL_TABLE, options)
        entities.each do |entity|
          storage_account_name = entity['RowKey']
          @logger.info("Delete records `#{entity['RowKey']}' whose PartitionKey is `#{entity['PartitionKey']}'")
          @table_manager.delete_entity(STEMCELL_TABLE, entity['PartitionKey'], entity['RowKey'])
        end
      end
    end

    def has_stemcell?(storage_account_name, name)
      @logger.info("has_stemcell?(#{storage_account_name}, #{name})")
      blob_properties = @blob_manager.get_blob_properties(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      !blob_properties.nil?
    end

    def get_user_image_info(stemcell_name, storage_account_type, location)
      @logger.info("get_user_image_info(#{stemcell_name}, #{storage_account_type}, #{location})")
      user_image = get_user_image(stemcell_name, storage_account_type, location)
      StemcellInfo.new(user_image[:id], user_image[:tags])
    end

    private

    def get_user_image(stemcell_name, storage_account_type, location)
      @logger.info("get_user_image(#{stemcell_name}, #{storage_account_type}, #{location})")
      user_image_name = "#{stemcell_name}-#{storage_account_type}-#{location}"
      user_image = @azure_client2.get_user_image_by_name(user_image_name)
      return user_image unless user_image.nil?

      default_storage_account = @storage_account_manager.default_storage_account
      default_storage_account_name = default_storage_account[:name]
      unless has_stemcell?(default_storage_account_name, stemcell_name)
        cloud_error("get_user_image: Failed to get user image for the stemcell `#{stemcell_name}' because the stemcell doesn't exist in the default storage account `#{default_storage_account_name}'")
      end

      storage_account_name = nil
      if location == default_storage_account[:location]
        storage_account_name = default_storage_account_name
      else
        mutex = FileMutex.new("#{BOSH_LOCK_CREATE_STORAGE_ACCOUNT}-#{location}", @logger)
        begin
          if mutex.lock
            storage_account = @azure_client2.list_storage_accounts().find{ |s|
              s[:location] == location && is_stemcell_storage_account?(s[:tags])
            }
            if storage_account.nil?
              storage_account_name = @storage_account_manager.generate_storage_account_name()
              @logger.info("get_user_image: Creating a storage account `#{storage_account_name}' with the tags `#{STEMCELL_STORAGE_ACCOUNT_TAGS}' in the location `#{location}'")
              @storage_account_manager.create_storage_account(storage_account_name, storage_account_type, location, STEMCELL_STORAGE_ACCOUNT_TAGS)
            end
            mutex.unlock
          else
            mutex.wait
          end
          storage_account = @azure_client2.list_storage_accounts().find{ |s|
            s[:location] == location && is_stemcell_storage_account?(s[:tags])
          }
          storage_account_name = storage_account[:name]
        rescue => e
          if e.message == BOSH_LOCK_EXCEPTION_TIMEOUT
            cloud_error("get_user_image: Failed to finish the creation of the storage account `#{storage_account_name}', `#{storage_account_type}' in location `#{location}' in #{mutex.expired} seconds.")
          end
          raise e
        end

        mutex = FileMutex.new("#{BOSH_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{storage_account_name}", @logger, BOSH_LOCK_COPY_STEMCELL_TIMEOUT)
        begin
          if mutex.lock
            unless has_stemcell?(storage_account_name, stemcell_name)
              @logger.info("get_user_image: Copying the stemcell from the default storage account `#{default_storage_account_name}' to the storage acccount `#{storage_account_name}'")
              stemcell_source_blob_uri = @blob_manager.get_blob_uri(default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd")
              @blob_manager.copy_blob(storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd", stemcell_source_blob_uri) do
                mutex.update()
              end
            end
            mutex.unlock
          else
            mutex.wait
          end
        rescue => e
          if e.message == BOSH_LOCK_EXCEPTION_TIMEOUT
            cloud_error("get_user_image: Failed to finish the copying process of the stemcell `#{stemcell_name}' from the default storage account `#{default_storage_account_name}' to the storage acccount `#{storage_account_name}' in `#{mutex.expired}' seconds.")
          end
          raise e
        end
      end

      stemcell_info = get_stemcell_info(storage_account_name, stemcell_name)
      user_image_params = {
        :name                => user_image_name,
        :location            => location,
        :tags                => stemcell_info.metadata,
        :os_type             => stemcell_info.os_type,
        :source_uri          => stemcell_info.uri,
        :account_type        => storage_account_type
      }
      begin
        mutex = FileMutex.new("#{BOSH_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", @logger)
        if mutex.lock
          @azure_client2.create_user_image(user_image_params)
          mutex.unlock
        else
          mutex.wait
        end
      rescue => e
        if e.message == BOSH_LOCK_EXCEPTION_TIMEOUT
          cloud_error("get_user_image: Failed to create the user image `#{user_image_name}' in #{mutex.expired} seconds.")
        end
        raise e
      end

      user_image = @azure_client2.get_user_image_by_name(user_image_name)
      cloud_error("get_user_image: Can not find a user image with the name `#{user_image_name}'") if user_image.nil?
      user_image
    end
  end
end
