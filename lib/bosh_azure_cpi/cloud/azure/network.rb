require 'azure'

module Bosh::AzureCloud
  class Network < Azure::VirtualNetworkManagement::VirtualNetwork
    attr_accessor :vnet_client, :spec

    ##
    # Creates a new network
    #
    # @param [Azure::VirtualMachineManagement::VirtualMachineManagementService] vnet_client
    # @param [Hash] spec Raw network spec
    def initialize(vnet_client, spec)
      unless spec.is_a?(Array)
        raise ArgumentError, 'Invalid spec, Array expected, ' \
                             "#{spec.class} provided"
      end

      @vnet_client = vnet_client
      @logger = Bosh::Clouds::Config.logger

      @spec = spec
      @cloud_properties = spec['cloud_properties']
    end

    def configure
      puts "`configure' not implemented by #{self.class}"
    end

    def eql?(other)
      return ((address_space.sort == other.address_space.sort) &&
              (affinity_group.eql? other.affinity_group) &&
              (dns_servers.sort == other.dns_servers.sort) &&
              (state.eql? other.state) &&
              (subnets.sort == other.subnets.sort))
    end
  end
end