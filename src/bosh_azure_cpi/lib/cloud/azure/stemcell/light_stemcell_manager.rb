# frozen_string_literal: true

module Bosh::AzureCloud
  class LightStemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, storage_account_manager, azure_client)
      @blob_manager = blob_manager
      @storage_account_manager = storage_account_manager
      @azure_client = azure_client
      @logger = Bosh::Clouds::Config.logger

      default_storage_account = @storage_account_manager.default_storage_account
      @default_storage_account_name = default_storage_account[:name]
      @default_location = default_storage_account[:location]
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")
      metadata = _get_metadata(name)
      @blob_manager.delete_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") unless metadata.nil?
    end

    def create_stemcell(stemcell_properties)
      @logger.info("create_stemcell(#{stemcell_properties})")
      cloud_error("Cannot find the light stemcell (#{stemcell_properties['image']}) in the location '#{@default_location}'") unless _platform_image_exists?(@default_location, stemcell_properties)

      stemcell_name = "#{LIGHT_STEMCELL_PREFIX}-#{SecureRandom.uuid}"
      metadata = stemcell_properties.dup
      metadata['image'] = JSON.dump(metadata['image'])
      @blob_manager.create_empty_page_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd", 1, metadata)
      stemcell_name
    end

    def has_stemcell?(location, name)
      @logger.info("has_stemcell?(#{location}, #{name})")
      metadata = _get_metadata(name)
      return false if metadata.nil?

      _platform_image_exists?(location, metadata)
    end

    def get_stemcell_info(name)
      @logger.info("get_stemcell_info(#{name})")
      metadata = _get_metadata(name)
      cloud_error("The light stemcell '#{name}' does not exist in the storage account '#{@default_storage_account_name}'") if metadata.nil?
      StemcellInfo.new('', metadata)
    end

    private

    def _get_metadata(name)
      metadata = @blob_manager.get_blob_metadata(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      return nil if metadata.nil?

      metadata['image'] = JSON.parse(metadata['image'])
      metadata
    end

    def _platform_image_exists?(location, stemcell_properties)
      stemcell_info = StemcellInfo.new('', stemcell_properties)
      @logger.debug("list_platform_image_versions(#{location}, #{stemcell_info.image['publisher']}, #{stemcell_info.image['offer']}, #{stemcell_info.image['sku']})")
      versions = @azure_client.list_platform_image_versions(location, stemcell_info.image['publisher'], stemcell_info.image['offer'], stemcell_info.image['sku'])
      version = versions.find { |v| v[:name] == stemcell_info.image['version'] }
      @logger.debug("list_platform_image_versions: The version '#{stemcell_info.image['version']}' of the image is not found") if version.nil?
      !version.nil?
    end
  end
end
