# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellManager2 < StemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, meta_store, storage_account_manager, azure_client)
      super(blob_manager, meta_store, storage_account_manager)
      @azure_client = azure_client
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")

      # Both the old format and new format of user image are deleted
      stemcell_uuid = name.sub("#{STEMCELL_PREFIX}-", '')
      user_images = @azure_client.list_user_images.select do |user_image|
        user_image[:name].start_with?(stemcell_uuid, name)
      end
      user_images.each do |user_image|
        user_image_name = user_image[:name]
        @logger.info("Delete user image '#{user_image_name}'")
        @azure_client.delete_user_image(user_image_name)
      end

      if @storage_account_manager.use_default_account_for_cleaning
        # Delete a stemcell name in defaukt storage accounts
        @logger.info("Delete stemcell(#{name}) in default storage account #{@default_storage_account_name}")
        @blob_manager.delete_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(@default_storage_account_name, name)
      else
        # Delete all stemcells with the given stemcell name in all storage accounts
        storage_accounts = @azure_client.list_storage_accounts
        storage_accounts.each do |storage_account|
          storage_account_name = storage_account[:name]
          @logger.info("Delete stemcell '#{name}' in the storage '#{storage_account_name}'")
          @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(storage_account_name, name)
        end
      end

      # Delete all records whose PartitionKey is the given stemcell name
      @meta_store.delete_stemcell_meta(name) if @meta_store.meta_enabled
    end

    def has_stemcell?(storage_account_name, name)
      @logger.info("has_stemcell?(#{storage_account_name}, #{name})")
      blob_properties = @blob_manager.get_blob_properties(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      !blob_properties.nil?
    end

    def get_user_image_info(stemcell_name, storage_account_type, location, https_traffic)
      @logger.info("get_user_image_info(#{stemcell_name}, #{storage_account_type}, #{location}, #{https_traffic})")
      user_image = _get_user_image(stemcell_name, storage_account_type, location, https_traffic)
      StemcellInfo.new(user_image[:id], user_image[:tags])
    end

    private

    def _get_user_image(stemcell_name, storage_account_type, location, https_traffic)
      @logger.info("_get_user_image(#{stemcell_name}, #{storage_account_type}, #{location}, #{https_traffic})")

      # The old user image name's length exceeds 80 in some location, which would cause the creation failure.
      # Old format: bosh-stemcell-<UUID>-Standard_LRS-<LOCATION>, bosh-stemcell-<UUID>-Premium_LRS-<LOCATION>
      # New format: <UUID>-S-<LOCATION>, <UUID>-P-<LOCATION>
      user_image_name_deprecated = "#{stemcell_name}-#{storage_account_type}-#{location}"
      user_image_name = user_image_name_deprecated.sub("#{STEMCELL_PREFIX}-", '')
                                                  .sub(STORAGE_ACCOUNT_TYPE_STANDARD_LRS, 'S')
                                                  .sub(STORAGE_ACCOUNT_TYPE_STANDARDSSD_LRS, 'SSSD')
                                                  .sub(STORAGE_ACCOUNT_TYPE_PREMIUM_LRS, 'P')
      user_image = @azure_client.get_user_image_by_name(user_image_name)
      return user_image unless user_image.nil?

      default_storage_account = @storage_account_manager.default_storage_account
      default_storage_account_name = default_storage_account[:name]
      cloud_error("get_user_image: Failed to get user image for the stemcell '#{stemcell_name}' because the stemcell doesn't exist in the default storage account '#{default_storage_account_name}'") unless has_stemcell?(default_storage_account_name, stemcell_name)

      storage_account_name = nil
      if location == default_storage_account[:location]
        storage_account_name = default_storage_account_name
      else
        # The storage account will only be used when preparing a stemcell in the target location for user image, ANY storage account type is ok.
        # To make it consistent, 'Standard_LRS' is used.
        storage_account = @storage_account_manager.get_or_create_storage_account_by_tags(STEMCELL_STORAGE_ACCOUNT_TAGS, STORAGE_ACCOUNT_TYPE_STANDARD_LRS, STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1, location, [STEMCELL_CONTAINER], false, https_traffic)
        storage_account_name = storage_account[:name]

        flock("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{storage_account_name}", File::LOCK_EX) do
          unless has_stemcell?(storage_account_name, stemcell_name)
            @logger.info("get_user_image: Copying the stemcell from the default storage account '#{default_storage_account_name}' to the storage acccount '#{storage_account_name}'")
            stemcell_source_blob_uri = get_stemcell_uri(default_storage_account_name, stemcell_name)
            @blob_manager.copy_blob(storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd", stemcell_source_blob_uri)
          end
        end
      end

      stemcell_info = get_stemcell_info(storage_account_name, stemcell_name)
      user_image_params = {
        name: user_image_name,
        location: location,
        tags: stemcell_info.metadata,
        os_type: stemcell_info.os_type,
        source_uri: stemcell_info.uri,
        account_type: storage_account_type
      }

      flock("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX) do
        user_image = @azure_client.get_user_image_by_name(user_image_name)
        if user_image.nil?
          @azure_client.delete_user_image(user_image_name_deprecated) # CPI will cleanup the user image with the old format name
          @azure_client.create_user_image(user_image_params)
          user_image = @azure_client.get_user_image_by_name(user_image_name)
          cloud_error("get_user_image: Can not find a user image with the name '#{user_image_name}'") if user_image.nil?
        end
      end

      user_image
    end
  end
end
