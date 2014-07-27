
module Bosh::AzureCloud
  class VirtualNetworkManager

    def initialize(vnet_client, affinity_group_manager)
      @vnet_client = vnet_client
      @ag_manager = affinity_group_manager
    end

    def exist?(name)
      @vnet_client.list_virtual_networks.each do |vnet|
        return true if vnet.name.eql? name
      end
      return false
    end

    def subnet_exist?(vnet_name, subnet_name)
      # TODO: Need to check if subnet exists
    end

    def create(name, affinity_group, subnets, dns_servers=[{:name => 'google_primary', :ip_address => '8.8.8.8'}, {:name => 'google_secondary', :ip_address => '8.8.4.4'}])
      raise if not exist?(name)
      if !@ag_manager.exist? affinity_group
        puts "Affinity group '#{affinity_group}' does not exist... Creating"
        @ag_manager.create name
      end

      address_space = ['10.0.0.0/8']
      # subnets = [{:name => 'subnet-1',  :ip_address=>'172.16.0.0',  :cidr=>12},  {:name => 'subnet-2',  :ip_address=>'10.0.0.0',  :cidr=>8}]
      validate_subnets subnets
      options = {:subnet => subnets, :dns => dns_servers}
      @vnet_client.set_network_configuration(name, affinity_group, address_space, options)
    end


    private

    def validate_subnets(subnets)
      subnets.each do |subnet|
        raise 'Malformed subnet given to virtual network. Format is' +
              "{:name => 'some_name', :ip_address => '10.x.x.x', :cidr => X}" if !subnet.include?(:name) ||
                                                                                 !subnet.include?(:ip_address) ||
                                                                                 !subnet.include?(:cidr)
      end
    end

    def find_similar_network(affinity_group, subnets)
      # TODO: Look for a subnet that matches the nesessary subnets, but doesnt necessarily have the same name
    end
  end
end