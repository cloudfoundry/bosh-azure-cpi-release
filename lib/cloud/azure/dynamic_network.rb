module Bosh::AzureCloud

  class DynamicNetwork < Network
    include Helpers

    attr_reader :virtual_network_name, :subnet_name

    # create dynamic network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      super
      if @cloud_properties.nil? || !@cloud_properties.has_key?("virtual_network_name")
        cloud_error("virtual_network_name required for dynamic network")
      end
      if @cloud_properties.nil? || !@cloud_properties.has_key?("subnet_name")
        cloud_error("subnet_name required for dynamic network")
      end
      @virtual_network_name = @cloud_properties["virtual_network_name"]
      @subnet_name = @cloud_properties["subnet_name"]
    end

    def vnet?
      true
    end

  end
end