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

      name = spec['name'] || raise("Missing required network property 'name'")
      address_space = spec['address_space'] || ['10.0.0.0/8']
      dns_servers = spec['dns'] || default_dns
      affinity_group = spec['affinity_group'] || raise("Missing required network property 'affinity_group'")
      @spec = spec
      @cloud_properties = spec['cloud_properties']

      # Azure expects these keys to be symbols, not strings
      dns_servers.symbolize_keys
    end

    def eql?(other)
      return ((address_space.sort == other.address_space.sort) &&
              (affinity_group.eql? other.affinity_group) &&
              (dns_servers.sort == other.dns_servers.sort) &&
              (state.eql? other.state) &&
              (subnets.sort == other.subnets.sort))
    end

    private

    def default_dns
      [{:name => 'google_primary', :ip_address => '8.8.8.8'},
       {:name => 'google_secondary', :ip_address => '8.8.4.4'}]
    end
  end
end