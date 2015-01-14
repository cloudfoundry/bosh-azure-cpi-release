require 'azure'

module Bosh::AzureCloud
  class Network
    attr_accessor :vnet_client, :name

    include Comparable
    ##
    # Creates a new network
    #
    # @param [Azure::VirtualMachineManagement::VirtualMachineManagementService] vnet_client
    # @param [Hash] spec Raw network spec
    def initialize(vnet_client, spec)
      unless spec.is_a?(Hash)
        raise ArgumentError, 'Invalid spec, Hash expected, ' \
                             "#{spec.class} provided"
      end

      @vnet_manager = vnet_client
      #@logger = bosh::Clouds::Config.logger

      @spec = spec
      @name = spec['vlan_name'] || raise("Missing required network property 'vlan_name'")
    end

    def provision
      raise "'provision' is not implemented for 'bosh::AzureCloud::Network'"
    end

    # TODO: This was defined when Network was a subclass of Azure Network object. Need to re-define (or probably define in children)
    # def eql?(other)
    #   return ((address_space.sort == other.address_space.sort) &&
    #           (affinity_group.eql? other.affinity_group) &&
    #           (dns_servers.sort == other.dns_servers.sort) &&
    #           (state.eql? other.state) &&
    #           (subnets.sort == other.subnets.sort))
    # end
  end
end