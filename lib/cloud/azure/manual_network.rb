module Bosh::AzureCloud
  ##
  #
  class ManualNetwork < Network

    attr_reader :virtual_network_name, :subnet_name

    # create manual network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      super
      if @cloud_properties.nil? || !@cloud_properties.has_key?("virtual_network_name")
        raise Bosh::Clouds::CloudError, "virtual_network_name required for manual network"
      end
      if @cloud_properties.nil? || !@cloud_properties.has_key?("subnet_name")
        raise Bosh::Clouds::CloudError, "subnet_name required for manual network"
      end
      @virtual_network_name = @cloud_properties["virtual_network_name"]
      @subnet_name = @cloud_properties["subnet_name"]
    end

    def private_ip
      @ip
    end

    def vnet?
      true
    end

  end
end