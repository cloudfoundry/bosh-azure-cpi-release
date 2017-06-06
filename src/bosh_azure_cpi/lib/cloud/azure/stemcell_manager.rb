module Bosh::AzureCloud
  class StemcellManager
    STEMCELL_STATUS_PENDING       = 'pending'
    STEMCELL_STATUS_SUCCESS       = 'success'
    DEFAULT_COPY_STEMCELL_TIMEOUT = 20 * 60 #seconds

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, table_manager, storage_account_manager)
      @blob_manager  = blob_manager
      @table_manager = table_manager
      @storage_account_manager = storage_account_manager
      @logger = Bosh::Clouds::Config.logger

      @default_storage_account_name = @storage_account_manager.default_storage_account_name
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")
      if @table_manager.has_table?(STEMCELL_TABLE)
        options = {
          :filter => "PartitionKey eq '#{name}'"
        }
        entities = @table_manager.query_entities(STEMCELL_TABLE, options)
        entities.each do |entity|
          storage_account_name = entity['RowKey']
          @logger.info("Delete stemcell #{name} in the storage #{storage_account_name}")
          blob_properties = @blob_manager.get_blob_properties(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
          @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") unless blob_properties.nil?
          @table_manager.delete_entity(STEMCELL_TABLE, entity['PartitionKey'], entity['RowKey'])
        end
      end

      @blob_manager.delete_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(@default_storage_account_name, name)
    end

    def create_stemcell(image_path, stemcell_properties)
      @logger.info("create_stemcell(#{image_path}, #{stemcell_properties})")

      stemcell_name = nil
      Dir.mktmpdir('sc-') do |tmp_dir|
        @logger.info("Unpacking image: #{image_path}")
        run_command("tar -zxf #{image_path} -C #{tmp_dir}")
        @logger.info("Start to upload VHD")
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
        handle_stemcell_in_different_storage_account(storage_account_name, name)
      end
    end

    def get_stemcell_uri(storage_account_name, name)
      @logger.info("get_stemcell_uri(#{storage_account_name}, #{name})")
      @blob_manager.get_blob_uri(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
    end

    def get_stemcell_info(storage_account_name, name)
      @logger.info("get_stemcell_info(#{storage_account_name}, #{name})")
      uri = @blob_manager.get_blob_uri(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      metadata = @blob_manager.get_blob_metadata(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      cloud_error("The stemcell `#{name}' does not exist in the storage account `#{storage_account_name}'") if metadata.nil?
      StemcellInfo.new(uri, metadata)
    end

    private

    def run_command(command)
      output, status = Open3.capture2e(command)
      if status.exitstatus != 0
        cloud_error("'#{command}' failed with exit status=#{status.exitstatus} [#{output}]")
      end
    end

    def handle_stemcell_in_different_storage_account(storage_account_name, name)
      options = {
        :filter => "PartitionKey eq '#{name}' and RowKey eq '#{storage_account_name}'"
      }

      entities = @table_manager.query_entities(STEMCELL_TABLE, options)
      if entities.size > 0
        entity = entities[0]
        if entity['Status'] == STEMCELL_STATUS_SUCCESS
          return true
        elsif entity['Status'] != STEMCELL_STATUS_PENDING
          cloud_error("The status of the stemcell #{name} in the storage account #{storage_account_name} is unknown: #{entity['Status']}")
        end

        # Another process is copying the same stemcell
        return wait_stemcell_copy(storage_account_name, name, timeout = DEFAULT_COPY_STEMCELL_TIMEOUT)
      else
        begin
          entity = {
            :PartitionKey => name,
            :RowKey       => storage_account_name,
            :Status       => STEMCELL_STATUS_PENDING
          }
          ret = @table_manager.insert_entity(STEMCELL_TABLE, entity)
          unless ret
            # Another process is copying the same stemcell
            return wait_stemcell_copy(storage_account_name, name, timeout = DEFAULT_COPY_STEMCELL_TIMEOUT)
          end

          # Create containers if they are missing.
          # Background: When users create a storage account without containers in it, and use that storage account for a resource pool,
          #             CPI will try to create related containers when copying stemcell to that storage account.
          @blob_manager.prepare(storage_account_name)

          @logger.info("Copy stemcell #{name} to #{storage_account_name}")
          source_blob_uri = get_stemcell_uri(@default_storage_account_name, name)
          @blob_manager.copy_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd", source_blob_uri)

          entities = @table_manager.query_entities(STEMCELL_TABLE, options)
          unless entities.size > 0
            cloud_error("Cannot find the stemcell record #{name}:#{storage_account_name} in the table #{STEMCELL_TABLE} in the default storage account #{@default_storage_account_name}")
          end
          entity = entities[0]
          entity['Status'] = STEMCELL_STATUS_SUCCESS
          @table_manager.update_entity(STEMCELL_TABLE, entity)
          true
        rescue => e
          ignore_exception{ @table_manager.delete_entity(STEMCELL_TABLE, name, storage_account_name) }
          ignore_exception{ @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") }
          raise e
        end
      end
    end

    def wait_stemcell_copy(storage_account_name, name, timeout = DEFAULT_COPY_STEMCELL_TIMEOUT)
      while true
        options = {
          :filter => "PartitionKey eq '#{name}' and RowKey eq '#{storage_account_name}'"
        }
        entities = @table_manager.query_entities(STEMCELL_TABLE, options)
        unless entities.size > 0
          cloud_error("Cannot find the stemcell #{name} in the table #{STEMCELL_TABLE} in the default storage account #{@default_storage_account_name}")
        end

        return true if entities[0]['Status'] == STEMCELL_STATUS_SUCCESS

        start_time   = entities[0]['Timestamp']
        current_time = Time.now
        if (current_time - start_time) > timeout
          @logger.info("The timestamp of the record is #{start_time}, current time is #{current_time}")
          @table_manager.delete_entity(STEMCELL_TABLE, name, storage_account_name)
          @blob_manager.delete_blob(storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
          cloud_error("The operation of copying the stemcell #{name} to the storage account #{storage_account_name} timeouts")
        end
        sleep(15)
      end
    end
  end
end
