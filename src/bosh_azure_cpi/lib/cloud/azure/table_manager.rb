module Bosh::AzureCloud
  class TableManager

    include Helpers

    def initialize(azure_properties, storage_account_manager, azure_client2)
      @azure_properties = azure_properties
      @storage_account_manager = storage_account_manager
      @azure_client2 = azure_client2
      @logger = Bosh::Clouds::Config.logger

      storage_account = @storage_account_manager.default_storage_account
      storage_account[:key] = @azure_client2.get_storage_account_keys_by_name(storage_account[:name])[0]
      azure_storage_client = initialize_azure_storage_client(storage_account, 'table')
      @table_service_client = azure_storage_client.table_client
      @table_service_client.with_filter(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter.new)
      @table_service_client.with_filter(Azure::Core::Http::DebugFilter.new) if is_debug_mode(@azure_properties)
    end

    def has_table?(table_name)
      @logger.info("has_table?(#{table_name})")
      begin
        options = merge_storage_common_options()
        @logger.info("has_table?: Calling get_table(#{table_name}, #{options})")
        @table_service_client.get_table(table_name, options)
        true
      rescue => e
        cloud_error("has_table?: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?("(404)")
        false
      end
    end

    def query_entities(table_name, options)
      @logger.info("query_entities(#{table_name}, #{options})")
      entities = Array.new
      while true do
        options = merge_storage_common_options(options)
        @logger.info("query_entities: Calling query_entities(#{table_name}, #{options})")
        records = @table_service_client.query_entities(table_name, options)
        records.each { |r| entities.push(r.properties) } if records.size > 0
        break if records.continuation_token.nil? || records.continuation_token.empty?
        options[:continuation_token] = records.continuation_token
      end
      entities
    end

    ##
    # Insert an entity to the table
    #
    # @param [String] table_name name of the table
    # @param [Hash] entity entity to insert
    # @return [Boolean] true if success; false if the entity already exists.
    def insert_entity(table_name, entity)
      @logger.info("insert_entity(#{table_name}, #{entity})")
      begin
        options = merge_storage_common_options()
        @logger.info("insert_entity: Calling insert_entity(#{table_name}, #{entity}, #{options})")
        @table_service_client.insert_entity(table_name, entity, options)
        true
      rescue => e
        # Azure EntityAlreadyExists (409) if the specified entity already exists.
        cloud_error("insert_entity: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?("(409)")
        false
      end
    end

    def delete_entity(table_name, partition_key, row_key)
      @logger.info("delete_entity(#{table_name}, #{partition_key}, #{row_key})")
      begin
        options = merge_storage_common_options()
        @logger.info("delete_entity: Calling delete_entity(#{table_name}, #{partition_key}, #{row_key}, #{options})")
        @table_service_client.delete_entity(table_name, partition_key, row_key, options)
      rescue => e
        cloud_error("delete_entity: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?("(404)")
      end
    end

    def update_entity(table_name, entity)
      @logger.info("update_entity(#{table_name}, #{entity})")
      options = merge_storage_common_options()
      @logger.info("update_entity: Calling update_entity(#{table_name}, #{entity}, #{options})")
      @table_service_client.update_entity(table_name, entity, options)
    end
  end
end
