module Bosh::AzureCloud

  class ManualNetwork < Network
    include Helpers

    attr_reader :resource_group_name, :virtual_network_name, :subnet_name

    # create manual network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      super

      if @cloud_properties.nil?
        cloud_error("cloud_properties required for manual network")
      end

      @resource_group_name = @cloud_properties["resource_group_name"]

      if @cloud_properties.has_key?("virtual_network_name")
        @virtual_network_name = @cloud_properties["virtual_network_name"]
      else
        cloud_error("virtual_network_name required for manual network")
      end

      if @cloud_properties.has_key?("subnet_name")
        @subnet_name = @cloud_properties["subnet_name"]
      else
        cloud_error("subnet_name required for manual network")
      end
    end

    def private_ip
      @ip
    end

    def vnet?
      true
    end

  end
end
