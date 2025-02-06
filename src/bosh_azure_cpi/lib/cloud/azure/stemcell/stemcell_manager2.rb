# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellManager2 < StemcellManager
    include Bosh::Exec
    include Helpers

    # TODO: Make replica count configurable in global config. Azure suggests 1:20 ratio for replicas to vms,
    # but at least 3 replicas are recommended for productions images.
    DEFAULT_REPLICA_COUNT = 3.freeze

    def initialize(azure_config, blob_manager, meta_store, storage_account_manager, azure_client)
      @azure_config = azure_config
      @azure_client = azure_client
      super(blob_manager, meta_store, storage_account_manager)
    end

    def create_stemcell(image_path, stemcell_properties)
      @logger.info("StemcellManager2.create_stemcell(#{image_path}, #{stemcell_properties})")
      return super(image_path, stemcell_properties) unless _compute_gallery_enabled?

      location = @azure_config.location
      cloud_error("Missing the property 'location' in the global configuration") if location.nil?

      @logger.debug("Creating new stemcell in compute gallery and stemcell_properties: #{stemcell_properties}")
      metadata = stemcell_properties.dup
      stemcell_series = metadata['name'].delete_prefix('bosh-azure-hyperv-ubuntu-').delete_suffix('-go_agent')
      version = _make_semver_compliant(metadata['version'])
      image = {
        'publisher' => metadata['infrastructure'],
        'offer' => metadata['os_distro'],
        'sku' => stemcell_series,
        'version' => version
      }
      metadata['image'] = JSON.dump(image)
      metadata['compute_gallery_name'] = @azure_config.compute_gallery_name
      metadata['compute_gallery_image_definition'] = stemcell_series

      @logger.debug("Uploading stemcell vhd to the default storage account with metadata: #{metadata}")

      stemcell_name = super(image_path, metadata)

      os_type = metadata['os_type'].nil? ? 'Linux' : metadata['os_type'].downcase.capitalize
      params = {
        'location' => location,
        'tags' => metadata.merge({'stemcell_name' => stemcell_name}).to_h,
        'osType' => os_type,
      }.merge(image)

      @logger.info("Ensuring compute gallery image definition for series: #{stemcell_series}")
      @azure_client.create_gallery_image_definition(@azure_config.compute_gallery_name, stemcell_series, params)

      @logger.info("Creating new image version for series: #{stemcell_series}")
      @azure_client.create_gallery_image_version(
        @azure_config.compute_gallery_name,
        stemcell_series,
        version,
        {
          'location' => location,
          'tags' => metadata.merge({'stemcell_name' => stemcell_name}).to_h,
          'storage_account_name' => @default_storage_account_name,
          'blob_uri' => @blob_manager.get_blob_uri(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd"),
          'replica_count' => DEFAULT_REPLICA_COUNT,
          'target_regions' => [location]
        }
      )

      stemcell_name
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

      if _compute_gallery_enabled?
        @logger.debug("Compute gallery is enabled. Try to delete gallery image for stemcell '#{name}'")
        metadata = _get_gallery_image_metadata(@default_storage_account_name, name)
        if metadata
          @logger.info("Delete gallery image version '#{metadata[:image_definition]}:#{metadata[:version]}'")
          @azure_client.delete_gallery_image_version(
            metadata[:gallery_name],
            metadata[:image_definition],
            metadata[:version]
          )
        else
          @logger.info("Gallery image metadata not found for stemcell '#{name}'")
        end
      end

      if @storage_account_manager.use_default_account_for_cleaning
        # Delete a stemcell name in default storage accounts
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

    def get_user_image_info(stemcell_name, storage_account_type, location)
      @logger.info("get_user_image_info(#{stemcell_name}, #{storage_account_type}, #{location})")

      if _compute_gallery_enabled?
        @logger.debug("Compute gallery is enabled. Try to get image in '#{location}' for stemcell '#{stemcell_name}'")
        gallery_image = _ensure_gallery_image_in_target_location(stemcell_name, location)

        unless gallery_image.nil?
          @logger.debug("Found gallery image: #{gallery_image[:name]}")
          return StemcellInfo.new(gallery_image[:id], gallery_image[:tags])
        end
      end

      user_image = _get_user_image(stemcell_name, storage_account_type, location)
      return StemcellInfo.new(user_image[:id], user_image[:tags])
    end

    private

    def _compute_gallery_enabled?
      !@azure_config.compute_gallery_name.nil? && !@azure_config.compute_gallery_name.empty?
    end

    def _make_semver_compliant(version)
      v = version.split('.')
      major = v[0]
      minor = v.length > 1 ? v[1] : 0
      patch = v.length > 2 ? v[2] : 0
      "#{major}.#{minor}.#{patch}"
    end

    def _ensure_gallery_image_in_target_location(stemcell_name, target_location)
      storage_account_name = @default_storage_account_name
      gallery_metadata = _get_gallery_image_metadata(storage_account_name, stemcell_name)
      unless gallery_metadata
        @logger.info("Gallery image metadata not found for stemcell '#{stemcell_name}'. Skip creating gallery image in target location '#{target_location}'")
        return nil
      end

      @logger.debug("Stemcell #{stemcell_name} should be uploaded in compute gallery '#{gallery_metadata[:gallery_name]}' as image '#{gallery_metadata[:image_definition]}:#{gallery_metadata[:version]}'")
      gallery_image = @azure_client.get_compute_gallery_image_version(
        gallery_metadata[:gallery_name],
        gallery_metadata[:image_definition],
        gallery_metadata[:version]
      )

      if gallery_image.nil?
        flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_metadata[:image_definition]}-#{gallery_metadata[:version]}", File::LOCK_EX) do
          @logger.info("Gallery image not found. Creating image '#{gallery_metadata[:image_definition]}:#{gallery_metadata[:version]}' in target location '#{target_location}'")
          gallery_image = @azure_client.create_gallery_image_version(
            gallery_metadata[:gallery_name],
            gallery_metadata[:image_definition],
            gallery_metadata[:version],
            {
              'location'             => target_location,
              'tags'                 => gallery_metadata[:tags],
              'storage_account_name' => storage_account_name,
              'blob_uri'             => @blob_manager.get_blob_uri(storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd"),
              'replica_count'        => DEFAULT_REPLICA_COUNT,
              'target_regions'       => [target_location]
            }
          )
        end
        return gallery_image
      end

      @logger.debug("Gallery image '#{gallery_metadata[:image_definition]}:#{gallery_metadata[:version]}' exists in gallery '#{gallery_metadata[:gallery_name]}'")
      regions = gallery_image[:target_regions]
      unless _contains_region?(regions, target_location)
        flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_metadata[:image_definition]}-#{gallery_metadata[:version]}", File::LOCK_EX) do
          @logger.info("Replicating the gallery image '#{gallery_metadata[:image_definition]}:#{gallery_metadata[:version]}' to target location '#{target_location}'")
          regions << target_location
          gallery_image = @azure_client.create_gallery_image_version(
            gallery_metadata[:gallery_name],
            gallery_metadata[:image_definition],
            gallery_metadata[:version],
            {
              'location'       => gallery_image[:location],
              'target_regions' => regions,
            }
          )
        end
      end

      gallery_image
    end

    def _contains_region?(region_list, region)
      region_list.any? do |r|
        r.delete(' ').downcase == region.delete(' ').downcase
      end
    end

    def _get_storage_account(stemcell_name, location)
      default_storage_account = @storage_account_manager.default_storage_account
      default_storage_account_name = default_storage_account[:name]
      cloud_error("Failed to get user image for the stemcell '#{stemcell_name}' because the stemcell doesn't exist in the default storage account '#{default_storage_account_name}'") unless has_stemcell?(default_storage_account_name, stemcell_name)

      return default_storage_account_name if location == default_storage_account[:location]

      # The storage account will only be used when preparing a stemcell in the target location for user image, ANY storage account type is ok.
      # To make it consistent, 'Standard_LRS' is used.
      storage_account = @storage_account_manager.get_or_create_storage_account_by_tags(STEMCELL_STORAGE_ACCOUNT_TAGS, STORAGE_ACCOUNT_TYPE_STANDARD_LRS, STORAGE_ACCOUNT_KIND_GENERAL_PURPOSE_V1, location, [STEMCELL_CONTAINER], false)
      storage_account_name = storage_account[:name]

      flock("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{storage_account_name}", File::LOCK_EX) do
        unless has_stemcell?(storage_account_name, stemcell_name)
          @logger.info("Copying the stemcell from the default storage account '#{default_storage_account_name}' to the storage acccount '#{storage_account_name}'")
          stemcell_source_blob_uri = get_stemcell_uri(default_storage_account_name, stemcell_name)
          @blob_manager.copy_blob(storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd", stemcell_source_blob_uri)
        end
      end

      storage_account_name
    end

    def _get_user_image(stemcell_name, storage_account_type, location)
      @logger.info("_get_user_image(#{stemcell_name}, #{storage_account_type}, #{location})")

      # The old user image name's length exceeds 80 in some location, which would cause the creation failure.
      # Old format: bosh-stemcell-<UUID>-Standard_LRS-<LOCATION>, bosh-stemcell-<UUID>-Premium_LRS-<LOCATION>
      # New format: <UUID>-S-<LOCATION>, <UUID>-P-<LOCATION>
      user_image_name_deprecated = "#{stemcell_name}-#{storage_account_type}-#{location}"
      user_image_name = user_image_name_deprecated.sub("#{STEMCELL_PREFIX}-", '')
                                                  .sub(STORAGE_ACCOUNT_TYPE_STANDARD_LRS, 'S')
                                                  .sub(STORAGE_ACCOUNT_TYPE_STANDARDSSD_LRS, 'SSSD')
                                                  .sub(STORAGE_ACCOUNT_TYPE_PREMIUM_LRS, 'P')

      # Lock GET operations to avoid using an image that is currently being created
      # Example:
      #   CPI Process 1: Get -> 404 -> image create -> create operation running
      #   CPI Process 2: Get -> 200 > VM create -> fails since image is still being created on Azure side
      user_image = nil
      flock("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX) do
        user_image = @azure_client.get_user_image_by_name(user_image_name)
      end

      return user_image unless user_image.nil?

      storage_account_name = _get_storage_account(stemcell_name, location)

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

    def _get_gallery_image_metadata(storage_account_name, stemcell_name)
      begin
        metadata = @blob_manager.get_blob_metadata(storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd")
        @logger.debug("Retrieved gallery image metadata from #{storage_account_name}/#{stemcell_name}: #{metadata}")
        return nil unless metadata&.key?('compute_gallery_name') &&
                         metadata.key?('compute_gallery_image_definition') &&
                         metadata.key?('image')

        image_metadata = JSON.parse(metadata['image'], symbolize_names: true)
        {
          gallery_name: metadata['compute_gallery_name'],
          image_definition: metadata['compute_gallery_image_definition'],
          version: image_metadata[:version],
          tags: metadata.merge({ 'stemcell_name' => stemcell_name }).to_h
        }
      rescue => e
        @logger.warn("Failed to retrieve metadata for gallery image: #{e.message}")
        nil
      end
    end
  end
end
