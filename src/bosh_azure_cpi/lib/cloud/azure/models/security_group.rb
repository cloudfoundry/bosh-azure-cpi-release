# frozen_string_literal: true

module Bosh::AzureCloud
  class SecurityGroup
    attr_reader :resource_group_name, :name

    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    NAME_KEY = 'name'

    def initialize(resource_group_name, name)
      @resource_group_name = resource_group_name
      @name = name
    end

    def self.parse_security_group(security_group_field)
      if security_group_field.is_a?(Hash)
        new(
          security_group_field[RESOURCE_GROUP_NAME_KEY],
          security_group_field[NAME_KEY]
        )
      else
        new(
          nil,
          security_group_field
        )
      end
    end

    def to_s
      "name: #{@name}, resource_group_name: #{@resource_group_name}"
    end
  end
end
