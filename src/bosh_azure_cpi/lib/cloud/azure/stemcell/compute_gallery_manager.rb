# frozen_string_literal: true

require 'digest'

module Bosh::AzureCloud
  class ComputeGalleryManager
    include Bosh::Exec
    include Helpers

    STEMCELL_PUBLISHER = 'bosh'.freeze
    DEFAULT_HYPERV_GENERATION = 'gen1'.freeze

    def initialize(azure_config, azure_client, blob_manager, default_storage_account_name)
      @azure_config = azure_config
      @azure_client = azure_client
      @blob_manager = blob_manager
      @default_storage_account_name = default_storage_account_name
      @logger = Bosh::Clouds::Config.logger
    end

    def enabled?
      !@azure_config.compute_gallery_name.nil? && !@azure_config.compute_gallery_name.empty?
    end

    def create_stemcell_with_gallery(image_path, stemcell_properties, blob_creation_callback)
      location = @azure_config.location
      cloud_error("Missing the property 'location' in the global configuration") if location.nil?

      metadata = stemcell_properties.dup
      stemcell_series = metadata['name']
      version = make_semver_compliant(metadata['version'])

      image_sha256 = calculate_image_sha256(image_path)
      @logger.info("Stemcell image SHA256 checksum: #{image_sha256}")

      image = {
        'publisher' => STEMCELL_PUBLISHER,
        'offer' => stemcell_series,
        'sku' => metadata.fetch('generation', DEFAULT_HYPERV_GENERATION),
        'version' => version
      }
      metadata['image'] = JSON.dump(image)
      metadata['compute_gallery_name'] = @azure_config.compute_gallery_name
      metadata['compute_gallery_image_definition'] = stemcell_series
      metadata['image_sha256'] = image_sha256

      @logger.info("Uploading stemcell vhd to the default storage account with metadata: #{metadata}")
      stemcell_name = blob_creation_callback.call(image_path, metadata)

      @logger.info("Creating gallery image definition and version for stemcell '#{stemcell_name}'")
      create_gallery_image(stemcell_name, stemcell_series, version, location, metadata)

      stemcell_name
    end

    def create_gallery_image(stemcell_name, image_definition, version, location, metadata)
      gallery_name = @azure_config.compute_gallery_name
      existing_image = get_existing_gallery_image(gallery_name, image_definition, version)

      if existing_image
        return update_existing_gallery_image(existing_image, stemcell_name, gallery_name, image_definition, version, metadata)
      end

      create_new_gallery_image(stemcell_name, gallery_name, image_definition, version, location, metadata)
    end

    def delete_gallery_image(gallery_image, stemcell_name)
      updated_tags = gallery_image[:tags].dup
      stemcell_refs = (updated_tags['stemcell_references'] || '').split(',').map(&:strip).reject(&:empty?)
      stemcell_name_matches = updated_tags['stemcell_name'] == stemcell_name
      stemcell_refs_includes = stemcell_refs.include?(stemcell_name)

      if stemcell_name_matches || stemcell_refs_includes
        stemcell_refs.delete(stemcell_name) if stemcell_refs_includes

        if stemcell_refs.empty?
          @logger.info("Delete gallery image version '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' (no more references)")
          @azure_client.delete_gallery_image_version(
            gallery_image[:gallery_name],
            gallery_image[:image_definition],
            gallery_image[:name]
          )
          return true
        else
          @logger.info("Remove stemcell '#{stemcell_name}' reference from gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}'")
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
          return false
        end
      end

      false
    end

    def find_gallery_image_by_stemcell_name(stemcell_name)
      @azure_client.get_gallery_image_version_by_stemcell_name(@azure_config.compute_gallery_name, stemcell_name)
    end

    def ensure_gallery_image_in_target_location(stemcell_name, target_location)
      gallery_image = find_gallery_image_by_stemcell_name(stemcell_name)

      if gallery_image.nil?
        return recover_gallery_image_from_blob_metadata(stemcell_name, target_location)
      end

      update_gallery_image_for_target_location(gallery_image, target_location)
    end

    private

    def get_existing_gallery_image(gallery_name, image_definition, version)
      begin
        @azure_client.get_gallery_image_version(gallery_name, image_definition, version)
      rescue => e
        @logger.debug("Gallery image version #{gallery_name}/#{image_definition}:#{version} does not exist (expected): #{e.message}")
        nil
      end
    end

    def update_existing_gallery_image(existing_image, stemcell_name, gallery_name, image_definition, version, metadata)
      if existing_image[:tags].nil? ||
         (existing_image[:tags]['stemcell_references'].nil? && existing_image[:tags]['stemcell_name'].nil?)
        cloud_error("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists but was not created by BOSH CPI. Please use a different stemcell version or delete the existing image.")
      end

      unless validate_sha256_checksum(existing_image[:tags], metadata)
        cloud_error("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists but has different content (SHA256 mismatch). Expected: #{metadata['image_sha256']}, Found: #{existing_image[:tags]['image_sha256']}. Please use a different stemcell version or verify the image integrity.")
      end

      @logger.info("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists, updating tags")
      updated_tags = build_updated_tags(existing_image[:tags], stemcell_name, metadata['image_sha256'])

      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}-#{version}", File::LOCK_EX) do
        @azure_client.create_update_gallery_image_version(
          gallery_name,
          image_definition,
          version,
          {
            'location' => existing_image[:location],
            'tags' => updated_tags
          }
        )
      end
    end

    def validate_sha256_checksum(existing_metadata, new_metadata)
      existing_sha256 = existing_metadata['image_sha256']
      new_sha256 = new_metadata['image_sha256']

      # If either checksum is missing, validation passes (for backwards compatibility)
      return true unless existing_sha256 && new_sha256

      existing_sha256 == new_sha256
    end

    def build_updated_tags(existing_tags, stemcell_name, image_sha256)
      updated_tags = existing_tags.dup
      existing_stemcells = (updated_tags['stemcell_references'] || '').split(',').map(&:strip).reject(&:empty?)

      if updated_tags['stemcell_name'] && !existing_stemcells.include?(updated_tags['stemcell_name'])
        existing_stemcells << updated_tags['stemcell_name']
      end

      existing_stemcells << stemcell_name unless existing_stemcells.include?(stemcell_name)
      updated_tags['stemcell_references'] = existing_stemcells.join(',')

      new_sha256 = image_sha256
      if new_sha256 && !updated_tags['image_sha256']
        updated_tags['image_sha256'] = new_sha256
      end

      updated_tags
    end

    def build_hyperv_generation(metadata)
      generation = metadata['generation'] || DEFAULT_HYPERV_GENERATION
      "V#{generation.delete_prefix('gen')}"
    end

    def create_new_gallery_image(stemcell_name, gallery_name, image_definition, version, location, metadata)
      os_type = metadata['os_type']&.downcase&.capitalize
      cloud_error("Invalid os_type '#{os_type}'") unless ['Linux', 'Windows'].include?(os_type)

      image_metadata = JSON.parse(metadata['image'])
      hyperv_generation = build_hyperv_generation(metadata)
      params = { 'location' => location, 'osType' => os_type, 'hyperVGeneration' => hyperv_generation }.merge(image_metadata)

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
            'replica_count'        => @azure_config.compute_gallery_replicas,
            'target_regions'       => [location]
          }
        )
      end

      gallery_image
    end

    def recover_gallery_image_from_blob_metadata(stemcell_name, target_location)
      @logger.debug("Gallery image not found for stemcell '#{stemcell_name}'. Try to recover from blob metadata")
      metadata = @blob_manager.get_blob_metadata(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd")

      return nil unless metadata&.key?('image') && metadata.key?('compute_gallery_name') && metadata.key?('compute_gallery_image_definition')
      return nil if metadata['compute_gallery_name'] != @azure_config.compute_gallery_name

      image_metadata = JSON.parse(metadata['image'], symbolize_names: true)
      @logger.debug("Recovering gallery image from metadata of blob '#{stemcell_name}': #{image_metadata}")
      create_gallery_image(stemcell_name, metadata['compute_gallery_image_definition'], image_metadata[:version], target_location, metadata)
    end

    def update_gallery_image_for_target_location(gallery_image, target_location)
      @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' found")
      needs_update = false
      params = { 'location' => gallery_image[:location] }

      unless contains_region?(gallery_image[:target_regions], target_location)
        @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' needs replication to target location '#{target_location}'")
        needs_update = true
        params['target_regions'] = gallery_image[:target_regions].dup.push(target_location)
      end

      current_replicas = gallery_image[:replica_count]
      if !current_replicas.nil? && current_replicas != @azure_config.compute_gallery_replicas
        @logger.debug("Gallery image '#{gallery_image[:gallery_name]}/#{gallery_image[:image_definition]}:#{gallery_image[:name]}' needs update of replicas from #{current_replicas} to #{@azure_config.compute_gallery_replicas}")
        needs_update = true
        params['replica_count'] = @azure_config.compute_gallery_replicas
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

    def contains_region?(region_list, region)
      region_list.any? do |r|
        r.delete(' ').downcase == region.delete(' ').downcase
      end
    end

    def calculate_image_sha256(image_path)
      @logger.debug("Starting SHA256 calculation for file: #{image_path}")
      cloud_error("Image file does not exist: #{image_path}") unless File.exist?(image_path)

      sha256 = Digest::SHA256.new
      File.open(image_path, 'rb') do |file|
        while chunk = file.read(8192)
          sha256.update(chunk)
        end
      end

      checksum = sha256.hexdigest
      @logger.debug("SHA256 calculation completed: #{checksum}")
      checksum
    end

    def make_semver_compliant(version)
      v = version.split('.')
      major = v[0]
      minor = v.length > 1 ? v[1] : 0
      patch = v.length > 2 ? v[2] : 0
      "#{major}.#{minor}.#{patch}"
    end
  end
end
