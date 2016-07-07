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

      unless @cloud_properties["virtual_network_name"].nil?
        @virtual_network_name = @cloud_properties["virtual_network_name"]
      else
        cloud_error("virtual_network_name required for dynamic network")
      end

      unless @cloud_properties["subnet_name"].nil?
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
