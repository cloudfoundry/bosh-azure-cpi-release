module Bosh::AzureCloud
  class DynamicNetwork < Network
    attr_reader :virtual_network_name, :subnet_name

    include Helpers
    def initialize(name, spec)
      super
      @virtual_network_name = (@cloud_properties.nil? || !@cloud_properties.has_key?("virtual_network_name")) ? nil : @cloud_properties["virtual_network_name"]
      @subnet_name = (@cloud_properties.nil? || !@cloud_properties.has_key?("subnet_name")) ? nil : @cloud_properties["subnet_name"]
    end

    def vnet?
      !(@virtual_network_name.nil? || @subnet_name.nil?)
    end

  end
end