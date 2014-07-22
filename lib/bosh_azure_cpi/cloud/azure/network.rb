require 'azure'

module Bosh::AzureCloud
  class Network < Azure::VirtualNetworkManagement::VirtualNetwork

    def eql?(other)
      return ((address_space.sort == other.address_space.sort) &&
              (affinity_group.eql? other.affinity_group) &&
              (dns_servers.sort == other.dns_servers.sort) &&
              (state.eql? other.state) &&
              (subnets.sort == other.subnets.sort))
    end
  end
end