
module Bosh::AzureCloud
  class VirtualNetworkManager

    def initialize(vnet_client, base_client)
      @vnet_client = vnet_client
      @base_client = base_client
    end

    def exist?(name)
      @vnet_client.list_virtual_networks.each do |vnet|
        return true if vnet.name eql? name
      end
      return false
    end

    def create(name, affinity_group, subnets, dns_servers=[{:name => 'google_primary', :ip_address => '8.8.8.8'}, {:name => 'google_secondary', :ip_address => '8.8.4.4'}])
      raise if not exist?(name)

      address_space = ['10.0.0.0/8']
      # subnets = [{:name => 'subnet-1',  :ip_address=>'172.16.0.0',  :cidr=>12},  {:name => 'subnet-2',  :ip_address=>'10.0.0.0',  :cidr=>8}]

      options = {:subnet => subnets, :dns => dns_servers}

      @vnet_client.set_network_configuration('virtual-network-name', 'affinity-group-name', address_space, options)
    end
  end
end