module Bosh::AzureCloud

  class DynamicNetwork < Network
    include Helpers

    attr_reader :resource_group_name, :virtual_network_name, :subnet_name

    # create dynamic network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      super

      if @cloud_properties.nil?
        cloud_error("cloud_properties required for dynamic network")
      end

      @resource_group_name = @cloud_properties["resource_group_name"]

      if @cloud_properties.has_key?("virtual_network_name")
        @virtual_network_name = @cloud_properties["virtual_network_name"]
      else
        cloud_error("virtual_network_name required for dynamic network")
      end

      if @cloud_properties.has_key?("subnet_name")
        @subnet_name = @cloud_properties["subnet_name"]
      else
        cloud_error("subnet_name required for dynamic network")
      end
    end

    def vnet?
      true
    end

  end
end
