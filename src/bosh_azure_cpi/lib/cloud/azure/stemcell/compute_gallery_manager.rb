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
      version = make_semver_compliant(metadata['version'])
      image_definition = build_image_definition_name(metadata)

      image_sha256 = calculate_image_sha256(image_path)
      @logger.info("Stemcell image SHA256 checksum: #{image_sha256}")

      image = {
        'publisher' => STEMCELL_PUBLISHER,
        'offer' => image_definition,
        'sku' => vm_generation(metadata),
        'version' => version
      }
      metadata['image'] = JSON.dump(image)
      metadata['compute_gallery_name'] = @azure_config.compute_gallery_name
      metadata['compute_gallery_image_definition'] = image_definition
      metadata['image_sha256'] = image_sha256

      @logger.info("Uploading stemcell vhd to the default storage account with metadata: #{metadata}")
      stemcell_name = blob_creation_callback.call(image_path, metadata)

      @logger.info("Creating gallery image definition and version for stemcell '#{stemcell_name}'")
      create_gallery_image(stemcell_name, image_definition, version, location, metadata)

      stemcell_name
    end

    def create_gallery_image(stemcell_name, image_definition, version, location, metadata)
      gallery_name = @azure_config.compute_gallery_name
      existing_image = @azure_client.get_gallery_image_version(gallery_name, image_definition, version)

      if existing_image
        return handle_existing_gallery_image(existing_image, stemcell_name, gallery_name, image_definition, version, metadata)
      end

      existing_definition = @azure_client.get_gallery_image_definition(gallery_name, image_definition)
      if existing_definition.nil?
        image_definition_params = build_image_definition_params(location, metadata)
        create_gallery_image_definition(gallery_name, image_definition, image_definition_params)
      else
        @logger.debug("Gallery image definition '#{gallery_name}/#{image_definition}' already exists, skipping creation")
      end

      image_version_params = build_image_version_params(stemcell_name, location, metadata)
      create_gallery_image_version(gallery_name, image_definition, version, image_version_params)
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

    def handle_existing_gallery_image(existing_image, stemcell_name, gallery_name, image_definition, version, metadata)
      existing_tags = existing_image[:tags]
      new_sha = metadata['image_sha256']

      unless validate_sha256_checksum(existing_tags, new_sha)
        cloud_error("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists but has different content (SHA256 mismatch). Expected: #{new_sha}, Found: #{existing_tags['image_sha256']}. Please use a different stemcell version or verify the image integrity.")
      end

      update_gallery_image_tags(existing_image, stemcell_name, gallery_name, image_definition, version, new_sha)
    end

    def update_gallery_image_tags(image, stemcell_name, gallery_name, image_definition, version, image_sha256)
      existing_tags = image[:tags]
      if existing_tags.nil? || (existing_tags['stemcell_references'].nil? && existing_tags['stemcell_name'].nil?)
        cloud_error("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists but was not created by BOSH CPI. Please use a different stemcell version or delete the existing image.")
      end

      @logger.info("Gallery image version #{gallery_name}/#{image_definition}:#{version} already exists, updating tags")
      updated_tags = build_updated_tags(existing_tags, stemcell_name, image_sha256)

      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}-#{version}", File::LOCK_EX) do
        @azure_client.create_update_gallery_image_version(
          gallery_name,
          image_definition,
          version,
          {
            'location' => image[:location],
            'tags' => updated_tags
          }
        )
      end
    end

    def validate_sha256_checksum(existing_metadata, new_sha256)
      existing_sha256 = existing_metadata['image_sha256']

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

      encode_metadata(updated_tags)
    end

    def normalize_os_type(os_type)
      normalized_os_type = os_type&.downcase&.capitalize
      unless ['Linux', 'Windows'].include?(normalized_os_type)
        cloud_error("Invalid os_type '#{os_type}'. Must be either 'Linux' or 'Windows'")
      end
      normalized_os_type
    end

    def normalize_architecture(arch)
      return nil if arch.nil? || arch.empty?
      case arch.to_s.downcase
      when 'x86_64', 'x64'
        'x64'
      when 'arm64'
        'Arm64'
      else
        arch
      end
    end

    def normalize_disk_controllers(disk_controllers)
      disk_controllers.map do |controller|
        case controller.to_s.downcase
        when 'scsi'
          'SCSI'
        when 'nvme'
          'NVMe'
        else
          controller
        end
      end
    end

    def build_hyperv_generation(metadata)
      generation = vm_generation(metadata).downcase
      "V#{generation.delete_prefix('gen')}"
    end

    def build_image_definition_params(location, metadata)
      os_type = normalize_os_type(metadata['os_type'])
      architecture = normalize_architecture(metadata['architecture'])
      image_metadata = JSON.parse(metadata['image'])
      hyperv_generation = build_hyperv_generation(metadata)
      features = build_features_array(metadata)

      params = {
        'location' => location,
        'osType' => os_type,
        'hyperVGeneration' => hyperv_generation
      }.merge(image_metadata)

      params['features'] = features if features
      params['architecture'] = architecture if architecture

      params
    end

    def build_image_version_params(stemcell_name, location, metadata)
      metadata_with_refs = metadata.dup
      metadata_with_refs['stemcell_references'] = stemcell_name

      {
        'location' => location,
        'tags' => encode_metadata(metadata_with_refs),
        'storage_account_name' => @default_storage_account_name,
        'blob_uri' => @blob_manager.get_blob_uri(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd"),
        'replica_count' => @azure_config.compute_gallery_replicas,
        'target_regions' => [location]
      }
    end

    def create_gallery_image_definition(gallery_name, image_definition, params)
      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}", File::LOCK_EX) do
        @logger.debug("Ensuring compute gallery image definition '#{gallery_name}/#{image_definition}'")
        @azure_client.create_gallery_image_definition(gallery_name, image_definition, params)
      end
    end

    def create_gallery_image_version(gallery_name, image_definition, version, params)
      gallery_image = nil
      flock("#{CPI_LOCK_CREATE_GALLERY_IMAGE}-#{gallery_name}-#{image_definition}-#{version}", File::LOCK_EX) do
        @logger.debug("Creating compute gallery image '#{gallery_name}/#{image_definition}:#{version}' in target location '#{params['location']}'")
        gallery_image = @azure_client.create_update_gallery_image_version(gallery_name, image_definition, version, params)
      end
      gallery_image
    end

    def recover_gallery_image_from_blob_metadata(stemcell_name, target_location)
      @logger.debug("Gallery image not found for stemcell '#{stemcell_name}'. Try to recover from blob metadata")

      metadata = get_blob_metadata_for_stemcell(stemcell_name)
      return nil unless metadata

      image_metadata = parse_metadata(metadata['image'])
      return nil unless image_metadata

      if metadata.key?('disk_controller_types')
        disk_controllers = parse_metadata(metadata['disk_controller_types'])
        metadata['disk_controller_types'] = disk_controllers if disk_controllers
      end

      @logger.debug("Recovering gallery image from metadata of blob '#{stemcell_name}': #{image_metadata}")
      create_gallery_image(stemcell_name, metadata['compute_gallery_image_definition'], image_metadata['version'], target_location, metadata)
    end

    def get_blob_metadata_for_stemcell(stemcell_name)
      begin
        metadata = @blob_manager.get_blob_metadata(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd")

        return nil unless metadata&.key?('image') &&
                         metadata.key?('compute_gallery_name') &&
                         metadata.key?('compute_gallery_image_definition')

        return nil if metadata['compute_gallery_name'] != @azure_config.compute_gallery_name

        metadata
      rescue => e
        @logger.warn("Failed to retrieve blob metadata for stemcell '#{stemcell_name}': #{e.message}")
        nil
      end
    end

    def parse_metadata(payload)
      return nil unless payload

      JSON.parse(payload)
    rescue JSON::ParserError => e
      @logger.warn("Failed to parse JSON metadata: #{e.message}")
      nil
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

    def build_features_array(metadata)
      return nil if gen1_image?(metadata)

      features = []

      if metadata.key?('disk_controller_types')
        disk_controllers = metadata['disk_controller_types']
        if disk_controllers.is_a?(Array) && !disk_controllers.empty?
          normalized_controllers = normalize_disk_controllers(disk_controllers)
          features << {
            'name' => 'DiskControllerTypes',
            'value' => normalized_controllers.join(',')
          }
        else
          @logger.warn("Ignoring invalid 'disk_controller_types' metadata: #{metadata['disk_controller_types']}")
        end
      end

      if metadata.key?('accelerated_networking')
        features << {
          'name' => 'IsAcceleratedNetworkSupported',
          'value' => metadata['accelerated_networking'] ? 'True' : 'False'
        }
      end

      if metadata.key?('hibernation')
        features << {
          'name' => 'IsHibernateSupported',
          'value' => metadata['hibernation'] ? 'True' : 'False'
        }
      end

      if metadata.key?('security_type')
        features << {
          'name' => 'SecurityType',
          'value' => metadata['security_type']
        }
      end

      features.empty? ? nil : features
    end

    def build_image_definition_name(metadata)
      metadata ||= {}
      name = metadata['name']
      cloud_error("Could not find stemcell name in metadata.") if name.nil?

      return name if gen1_image?(metadata)

      "#{name}-#{vm_generation(metadata)}"
    end

    def vm_generation(metadata)
      metadata ||= {}
      metadata['generation'] || DEFAULT_HYPERV_GENERATION
    end

    def gen1_image?(metadata)
      vm_generation(metadata).downcase == 'gen1'
    end
  end
end
