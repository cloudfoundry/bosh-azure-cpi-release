# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellManager2 < StemcellManager
    include Bosh::Exec
    include Helpers

    STEMCELL_PUBLISHER = 'bosh'.freeze
    DEFAULT_HYPERV_GENERATION = 'gen1'.freeze

    def initialize(azure_config, blob_manager, meta_store, storage_account_manager, azure_client)
      @azure_config = azure_config
      @azure_client = azure_client
      @replica_count = @azure_config.compute_gallery_replicas
      super(blob_manager, meta_store, storage_account_manager)
    end

    def create_stemcell(image_path, stemcell_properties)
      @logger.info("StemcellManager2.create_stemcell(#{image_path}, #{stemcell_properties})")
      return super(image_path, stemcell_properties) unless _compute_gallery_enabled?

      location = @azure_config.location
      cloud_error("Missing the property 'location' in the global configuration") if location.nil?

      metadata = stemcell_properties.dup
      stemcell_series = metadata['name']
      version = _make_semver_compliant(metadata['version'])
      image = {
        'publisher' => STEMCELL_PUBLISHER,
        'offer' => stemcell_series,
        'sku' => metadata.fetch('generation', DEFAULT_HYPERV_GENERATION),
        'version' => version
      }
      metadata['image'] = JSON.dump(image)
      metadata['compute_gallery_name'] = @azure_config.compute_gallery_name
      metadata['compute_gallery_image_definition'] = stemcell_series

      @logger.info("Uploading stemcell vhd to the default storage account with metadata: #{metadata}")
      stemcell_name = super(image_path, metadata)

      @logger.info("Creating gallery image definition and version for stemcell '#{stemcell_name}'")
      _create_gallery_image(stemcell_name, stemcell_series, version, location, metadata)

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
        gallery_image = @azure_client.get_gallery_image_version_by_stemcell_name(@azure_config.compute_gallery_name, name)

        if gallery_image.nil?
          @logger.info("No gallery image found for stemcell '#{name}'")
        else
          updated_tags = gallery_image[:tags].dup
          stemcell_refs = (updated_tags['stemcell_references'] || '').split(',').map(&:strip).reject(&:empty?)
          stemcell_name_matches = updated_tags['stemcell_name'] == name
          stemcell_refs_includes = stemcell_refs.include?(name)

          # Checking both, stemcell_name and stemcell_references for backwards-compatability
          if stemcell_name_matches || stemcell_refs_includes
            stemcell_refs.delete(name) if stemcell_refs_includes

            if stemcell_refs.empty?
              @logger.info("Delete gallery image version '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' (no more references)")
              @azure_client.delete_gallery_image_version(
                gallery_image[:gallery_name],
                gallery_image[:image_definition],
                gallery_image[:name]
              )
            else
              @logger.info("Remove stemcell '#{name}' reference from gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}'")
              updated_tags['stemcell_references'] = stemcell_refs.join(',')

              @azure_client.create_update_gallery_image_version(
                gallery_image[:gallery_name],
                gallery_image[:image_definition],
                gallery_image[:name],
                {
                  'location' => gallery_image[:location],
                  'tags' => updated_tags
                }
              )
            end
          end
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
          @logger.debug("Using gallery image: #{gallery_image[:id]}")
          return StemcellInfo.new(gallery_image[:id], gallery_image[:tags])
        end
      end

      @logger.debug("Try to get user image in '#{location}' for stemcell '#{stemcell_name}'")
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

    def _create_gallery_image(stemcell_name, image_definition, version, location, metadata)
      gallery_name = @azure_config.compute_gallery_name
      os_type = metadata['os_type']&.downcase&.capitalize
      cloud_error("Invalid os_type '#{os_type}'") unless ['Linux', 'Windows'].include?(os_type)

      existing_image = nil
      begin
        existing_image = @azure_client.get_gallery_image_version(gallery_name, image_definition, version)
      rescue => e
        @logger.debug("Gallery image version #{gallery_name}/#{image_definition}:#{version} does not exist (expected): #{e.message}")
      end

      if existing_image
        if existing_image[:tags].nil? ||
           (existing_image[:tags]['stemcell_references'].nil? && existing_image[:tags]['stemcell_name'].nil?)
          cloud_error("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists but was not created by BOSH CPI. Please use a different stemcell version or delete the existing image.")
        end

        @logger.info("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists, updating tags")
        updated_tags = existing_image[:tags].dup
        existing_stemcells = (updated_tags['stemcell_references'] || '').split(',').map(&:strip).reject(&:empty?)
        existing_stemcells << updated_tags['stemcell_name'] unless existing_stemcells.include?(updated_tags['stemcell_name'])
        existing_stemcells << stemcell_name unless existing_stemcells.include?(stemcell_name)
        updated_tags['stemcell_references'] = existing_stemcells.join(',')

        flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}-#{version}", File::LOCK_EX) do
          existing_image = @azure_client.create_update_gallery_image_version(
            gallery_name,
            image_definition,
            version,
            {
              'location' => existing_image[:location],
              'tags' => updated_tags
            }
          )
        end
        return existing_image
      end

      hyperVGeneration = "V#{(metadata['generation'] || DEFAULT_HYPERV_GENERATION).delete_prefix('gen')}"
      params = { 'location' => location, 'osType' => os_type, 'hyperVGeneration' => hyperVGeneration }.merge(JSON.parse(metadata['image']))
      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}", File::LOCK_EX) do
        @logger.debug("Ensuring compute gallery image definition '#{gallery_name}/#{image_definition}'")
        @azure_client.create_gallery_image_definition(gallery_name, image_definition, params)
      end

      gallery_image = nil
      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}-#{version}", File::LOCK_EX) do
        @logger.debug("Creating compute gallery image '#{gallery_name}/#{image_definition}:#{version}' in target location '#{location}'")
        metadata['stemcell_references'] = stemcell_name
        gallery_image = @azure_client.create_update_gallery_image_version(
          gallery_name,
          image_definition,
          version,
          {
            'location'             => location,
            'tags'                 => metadata,
            'storage_account_name' => @default_storage_account_name,
            'blob_uri'             => @blob_manager.get_blob_uri(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd"),
            'replica_count'        => @replica_count,
            'target_regions'       => [location]
          }
        )
      end

      gallery_image
    end

    def _ensure_gallery_image_in_target_location(stemcell_name, target_location)
      gallery_image = @azure_client.get_gallery_image_version_by_stemcell_name(@azure_config.compute_gallery_name, stemcell_name)

      if gallery_image.nil?
        @logger.debug("Gallery image not found for stemcell '#{stemcell_name}'. Try to recover from blob metadata")
        metadata = @blob_manager.get_blob_metadata(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd")
        return nil unless metadata&.key?('image') && metadata.key?('compute_gallery_name') && metadata.key?('compute_gallery_image_definition')
        return nil if metadata['compute_gallery_name'] != @azure_config.compute_gallery_name

        image_metadata = JSON.parse(metadata['image'], symbolize_names: true)
        @logger.debug("Recovering gallery image from metadata of blob '#{stemcell_name}': #{image_metadata}")
        return _create_gallery_image(stemcell_name, metadata['compute_gallery_image_definition'], image_metadata[:version], target_location, metadata)
      end

      @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' found")
      needs_update = false
      params = { 'location' => gallery_image[:location] }
      unless _contains_region?(gallery_image[:target_regions], target_location)
        @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' needs replication to target location '#{target_location}'")
        needs_update = true
        params['target_regions'] = gallery_image[:target_regions].dup.push(target_location)
      end

      current_replicas = gallery_image[:replica_count]
      if !current_replicas.nil? && current_replicas != @replica_count
        @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' needs update of replicas from #{current_replicas} to #{@replica_count}")
        needs_update = true
        params['replica_count'] = @replica_count
      end

      if needs_update
        flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_image[:image_definition]}-#{gallery_image[:name]}", File::LOCK_EX) do
          gallery_image = @azure_client.create_update_gallery_image_version(
            gallery_image[:gallery_name],
            gallery_image[:image_definition],
            gallery_image[:name],
            params
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
  end
end
