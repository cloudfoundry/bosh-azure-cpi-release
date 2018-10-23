# frozen_string_literal: true

module Bosh::AzureCloud
  class MetaStore
    include Helpers

    def initialize(table_manager)
      @table_manager = table_manager
    end

    def meta_enabled
      @table_manager.has_table?(STEMCELL_TABLE)
    end

    def find_stemcell_meta(name, storage_account_name = nil)
      entities = _query_table(name, storage_account_name)
      stemcell_metas = []
      entities.each do |entity|
        stemcell_meta = Bosh::AzureCloud::StemcellMeta.new(entity['PartitionKey'], entity['RowKey'], entity['Timestamp'])
        stemcell_metas.push(stemcell_meta)
      end
      stemcell_metas
    end

    def find_first_stemcell_meta(name, storage_account_name)
      entities = _query_table(name, storage_account_name)
      if entities.empty?
        nil
      else
        Bosh::AzureCloud::StemcellMeta.new(entities[0]['PartitionKey'], entities[0]['RowKey'], entities[0]['Status'], entities[0]['Timestamp'])
      end
    end

    def insert_stemcell_meta(stemcell_meta)
      entity = {
        PartitionKey: stemcell_meta.name,
        RowKey: stemcell_meta.storage_account_name,
        Status: stemcell_meta.status
      }
      @table_manager.insert_entity(STEMCELL_TABLE, entity)
    end

    def update_stemcell_meta(stemcell_meta)
      entity = {
        PartitionKey: stemcell_meta.name,
        RowKey: stemcell_meta.storage_account_name,
        Status: stemcell_meta.status
      }

      @table_manager.update_entity(STEMCELL_TABLE, entity)
    end

    def delete_stemcell_meta(name, storage_account_name = nil)
      if storage_account_name.nil?
        entities = _query_table(name, nil)
        entities.each do |entity|
          CPILogger.instance.logger.info("Delete records '#{entity['RowKey']}' whose PartitionKey is '#{entity['PartitionKey']}'")
          @table_manager.delete_entity(STEMCELL_TABLE, entity['PartitionKey'], entity['RowKey'])
        end
      else
        @table_manager.delete_entity(STEMCELL_TABLE, name, storage_account_name)
      end
    end

    private

    def _query_table(name, storage_account_name)
      filter = "PartitionKey eq '#{name}'"
      filter += " and RowKey eq '#{storage_account_name}'" unless storage_account_name.nil?
      options = {
        filter: filter
      }

      @table_manager.query_entities(STEMCELL_TABLE, options)
    end
  end
end
