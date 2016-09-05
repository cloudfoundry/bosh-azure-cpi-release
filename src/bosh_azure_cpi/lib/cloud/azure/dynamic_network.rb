module Bosh::AzureCloud

  class DynamicNetwork < Network
    include Helpers

    attr_reader :virtual_network_name, :subnet_name, :security_group

    # create dynamic network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(azure_properties, name, spec)
      super

      if @cloud_properties.nil?
        cloud_error("cloud_properties required for dynamic network")
      end

      @security_group = @cloud_properties["security_group"]

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

    def dns
      @spec["dns"]
    end

    def has_default_dns?
      !@spec["default"].nil? && @spec["default"].include?("dns")
    end

    def has_default_gateway?
      !@spec["default"].nil? && @spec["default"].include?("gateway")
    end
  end
end
