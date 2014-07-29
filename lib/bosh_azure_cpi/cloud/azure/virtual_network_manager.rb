require 'bosh/registry/config'

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

    def create(network_spec)
      raise if not exist?(name)

      @logger = Bosh::Clouds::Config.logger
      @network = nil
      @vip_network = nil

      network_spec.each do |spec|
        network_type = spec['type'] || 'dynamic'
        case network_type
          when 'dynamic'
            puts "More than one dynamic network for '#{name}'" && next if @network
            @network = DynamicNetwork.new(@vnet_client, spec) # For now, will short-circuit with auto-assiged public ip


          when 'vip'
            puts "More than one vip network for '#{name}'" && next if @vip_network
            @vip_network = VipNetwork.new(@vnet_client, spec)

          else
            puts "Invalid network type '#{network_type}' for Azure, " \
                 "can only handle 'dynamic' or 'vip' network types"
        end

        # TODO: Need to put managers in array for cleaner code and to finish
        check_affinity_group(@network.affinity_group) if @network
        check_affinity_group(@vip_network.affinity_group) if @vip_network

      #address_space = ['10.0.0.0/8']
      # subnets = [{:name => 'subnet-1',  :ip_address=>'172.16.0.0',  :cidr=>12},  {:name => 'subnet-2',  :ip_address=>'10.0.0.0',  :cidr=>8}]
      #validate_subnets subnets
      #options = {:subnet => subnets, :dns => dns_servers}
      #@vnet_client.set_network_configuration(name, affinity_group, address_space, options)
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

    def check_affinity_group(name)
      if !@ag_manager.exist? name
        puts "Affinity group '#{name}' does not exist... Creating..."
        @ag_manager.create name
      end
    end
  end
end