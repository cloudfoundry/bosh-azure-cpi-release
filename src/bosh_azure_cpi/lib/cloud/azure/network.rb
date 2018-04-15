module Bosh::AzureCloud
  class Network

    attr_reader :resource_group_name

    ##
    # Creates a new network
    #
    # @azure_properties Azure global configurations
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(azure_properties, name, spec)
      unless spec.is_a?(Hash)
        raise ArgumentError, "Invalid spec, Hash expected, " \
                             "#{spec.class} provided"
      end

      @logger = Bosh::Clouds::Config.logger
      @azure_properties = azure_properties
      @name = name
      @ip = spec["ip"]
      @cloud_properties = spec["cloud_properties"]
      @spec = spec
      unless @cloud_properties.nil? || @cloud_properties["resource_group_name"].nil?
        @resource_group_name = @cloud_properties["resource_group_name"]
      else
        @resource_group_name = @azure_properties["resource_group_name"]
      end
    end

    def spec
      @spec
    end
  end
end
