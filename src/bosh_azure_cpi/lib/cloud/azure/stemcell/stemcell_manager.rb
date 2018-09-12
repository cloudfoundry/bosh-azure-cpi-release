# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellManager
    STEMCELL_STATUS_PENDING       = 'pending'
    STEMCELL_STATUS_SUCCESS       = 'success'
    DEFAULT_COPY_STEMCELL_TIMEOUT = 20 * 60 # seconds
    WAIT_STEMCELL_COPY_INTERVAL   = 3 # seconds

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, meta_store, storage_account_manager)
      @blob_manager = blob_manager
      @meta_store = meta_store
      @storage_account_manager = storage_account_manager
      @logger = Bosh::Clouds::Config.logger

      @default_storage_account_name = @storage_account_manager.default_storage_account_name
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")
      if @meta_store.meta_enabled
        stemcell_metas = @meta_store.find_stemcell_meta(name)
        stemcell_metas.each do |stemcell_meta|
          @logger.info("Delete stemcell #{name} in the storage #{stemcell_meta.storage_account_name}")
          blob_properties = @blob_manager.get_blob_properties(stemcell_meta.storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
          @blob_manager.delete_blob(stemcell_meta.storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") unless blob_properties.nil?
          @meta_store.delete_stemcell_meta(stemcell_meta.name, stemcell_meta.storage_account_name)
        end
      end

      @blob_manager.delete_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(@default_storage_account_name, name)
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

    def has_stemcell?(storage_account_name, name)
      @logger.info("has_stemcell?(#{storage_account_name}, #{name})")
      if storage_account_name == @default_storage_account_name
        blob_properties = @blob_manager.get_blob_properties(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
        !blob_properties.nil?
      else
        _handle_stemcell_in_different_storage_account(storage_account_name, name)
      end
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

    private

    def _handle_stemcell_in_different_storage_account(storage_account_name, name)
      stemcell_meta = @meta_store.find_first_stemcell_meta(name, storage_account_name)
      if !stemcell_meta.nil?
        if stemcell_meta.status == STEMCELL_STATUS_SUCCESS
          true
        elsif stemcell_meta.status != STEMCELL_STATUS_PENDING
          cloud_error("The status of the stemcell #{name} in the storage account #{storage_account_name} is unknown: #{stemcell_meta.status}")
        end

        return _wait_stemcell_copy(storage_account_name, name)
      else
        begin
          stemcell_meta = Bosh::AzureCloud::StemcellMeta.new(name, storage_account_name, STEMCELL_STATUS_PENDING)
          insert_success = @meta_store.insert_stemcell_meta(stemcell_meta)
          return _wait_stemcell_copy(storage_account_name, name) unless insert_success

          @logger.info("Copying stemcell #{name} to #{storage_account_name}")
          source_blob_uri = get_stemcell_uri(@default_storage_account_name, name)
          @blob_manager.copy_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd", source_blob_uri)

          stemcell_meta = @meta_store.find_first_stemcell_meta(name, storage_account_name)
          cloud_error("Cannot find the stemcell record #{name}:#{storage_account_name} in the table #{STEMCELL_TABLE} in the default storage account #{@default_storage_account_name}") if stemcell_meta.nil?
          stemcell_meta.status = STEMCELL_STATUS_SUCCESS
          @meta_store.update_stemcell_meta(stemcell_meta)
          true
        rescue StandardError => e
          ignore_exception { @meta_store.delete_stemcell_meta(name, storage_account_name) }
          ignore_exception { @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") }
          raise e
        end
      end
    end

    def _wait_stemcell_copy(storage_account_name, name, timeout = DEFAULT_COPY_STEMCELL_TIMEOUT)
      @logger.info('Another process is copying the same stemcell')
      loop do
        stemcell_meta = @meta_store.find_first_stemcell_meta(name, storage_account_name)
        cloud_error("Cannot find the stemcell #{name} in the table #{STEMCELL_TABLE} in the default storage account #{@default_storage_account_name}") if stemcell_meta.nil?

        return true if stemcell_meta.status == STEMCELL_STATUS_SUCCESS

        start_time = stemcell_meta.timestamp
        start_time = Time.parse(start_time) if start_time.is_a?(String)
        current_time = Time.new
        if (current_time - start_time) > timeout
          @logger.info("The timestamp of the record is #{start_time}, current time is #{current_time}")
          @meta_store.delete_stemcell_meta(name, storage_account_name)
          @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
          cloud_error("The operation of copying the stemcell #{name} to the storage account #{storage_account_name} timeouts")
        end
        sleep(WAIT_STEMCELL_COPY_INTERVAL)
      end
    end
  end
end
