# frozen_string_literal: true

module Bosh::AzureCloud
  class ResObjectId < ObjectId
    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    # Params:
    # - id: the id string
    # - default_resource_group_name: the default resource group name in global config.
    def self.parse_with_resource_group(id_str, default_resource_group_name)
      ObjectId.parse_with_defaults(id_str, RESOURCE_GROUP_NAME_KEY => default_resource_group_name)
    end

    def resource_group_name
      @id_hash[RESOURCE_GROUP_NAME_KEY]
    end
  end
end
