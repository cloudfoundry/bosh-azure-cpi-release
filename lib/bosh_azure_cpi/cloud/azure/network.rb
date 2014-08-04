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

      @vnet_client = vnet_client
      #@logger = Bosh::Clouds::Config.logger

      @spec = spec
      @name = spec['vlan_name'] || raise("Missing required network property 'vlan_name'")

      # TODO: Find a better/cleaner way?
      dns_servers_sym = []
      # Azure expects these keys to be symbols, not strings
      @dns_servers.each do |dns_server|
        dns_servers_sym << symbolize_keys(dns_server)
      end

      # Re-assign it back
      @dns_servers = dns_servers_sym
    end

    def provision
      raise "'provision' is not implemented for 'Bosh::AzureCloud::Network'"
    end

    def eql?(other)
      return ((address_space.sort == other.address_space.sort) &&
              (affinity_group.eql? other.affinity_group) &&
              (dns_servers.sort == other.dns_servers.sort) &&
              (state.eql? other.state) &&
              (subnets.sort == other.subnets.sort))
    end


    private

    # TODO: Need to extract this to helpers
    # Converts all keys of a [Hash] to symbols. Performs deep conversion.
    #
    # @param [Hash] hash to convert
    # @return [Hash] a copy of the original hash
    def symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        h
      end
    end
  end
end