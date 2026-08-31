# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, meta_store, storage_account_manager)
      @blob_manager = blob_manager
      @meta_store = meta_store
      @storage_account_manager = storage_account_manager
      @logger = Bosh::Clouds::Config.logger

      @default_storage_account_name = @storage_account_manager.default_storage_account_name
    end

    def create_stemcell(image_path, stemcell_properties)
      @logger.info("create_stemcell(#{image_path}, #{stemcell_properties})")

      stemcell_name = nil
      Dir.mktmpdir('sc-') do |tmp_dir|
        @logger.info("Unpacking image: #{image_path}")
        command_runner = CommandRunner.new
        command_runner.run_command("tar -zxf #{image_path} -C #{tmp_dir}")
        @logger.info('Start to upload VHD')
        stemcell_name = "#{STEMCELL_PREFIX}-#{SecureRandom.uuid}"
        @logger.info("Upload the stemcell #{stemcell_name} to the storage account #{@default_storage_account_name}")
        @blob_manager.create_page_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{tmp_dir}/root.vhd", "#{stemcell_name}.vhd", stemcell_properties)
      end
      stemcell_name
    end

    def get_stemcell_uri(storage_account_name, name)
      @logger.info("get_stemcell_uri(#{storage_account_name}, #{name})")
      @blob_manager.get_sas_blob_uri(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
    end

    def get_stemcell_info(storage_account_name, name)
      @logger.info("get_stemcell_info(#{storage_account_name}, #{name})")
      uri = @blob_manager.get_blob_uri(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      metadata = @blob_manager.get_blob_metadata(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      cloud_error("The stemcell '#{name}' does not exist in the storage account '#{storage_account_name}'") if metadata.nil?
      StemcellInfo.new(uri, metadata)
    end
  end
end
