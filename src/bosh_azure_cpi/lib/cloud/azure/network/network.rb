# frozen_string_literal: true

module Bosh::AzureCloud
  class Network
    attr_reader :resource_group_name
    attr_reader :spec

    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    ##
    # Creates a new network
    #
    # @azure_config Azure global configurations
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(azure_config, name, spec)
      unless spec.is_a?(Hash)
        raise ArgumentError, 'Invalid spec, Hash expected, ' \
                             "#{spec.class} provided"
      end

      @azure_config = azure_config
      @name = name
      @ip = spec['ip']
      @cloud_properties = spec['cloud_properties']
      @spec = spec
      @resource_group_name = if @cloud_properties.nil? || @cloud_properties[RESOURCE_GROUP_NAME_KEY].nil?
                               @azure_config.resource_group_name
                             else
                               @cloud_properties[RESOURCE_GROUP_NAME_KEY]
                             end
    end
  end
end
