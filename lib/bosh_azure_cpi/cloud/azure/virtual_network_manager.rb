require 'bosh/registry/config'

require_relative 'dynamic_network'
require_relative 'vip_network'

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

      #@logger = Bosh::Clouds::Config.logger
      @network = nil
      @vip_network = nil

      # TODO: Need to fix affinity_group accessor.
      network_spec.each do |spec|
        network_type = spec['type'] || 'dynamic'
        case network_type
          when 'dynamic'
            puts "More than one dynamic network for '#{name}'" && next if @network
            @network = DynamicNetwork.new(@vnet_client, spec) # For now, will short-circuit with auto-assiged public ip
            check_affinity_group(@network.spec['affinity_group'])
            @network.provision

          when 'vip'
            puts "More than one vip network for '#{name}'" && next if @vip_network
            @vip_network = VipNetwork.new(@vnet_client, spec)
            check_affinity_group(@vip_network.spec['affinity_group'])
            @vip_network.provision

          else
            puts "Invalid network type '#{network_type}' for Azure, " \
                 "can only handle 'dynamic' or 'vip' network types"
        end
      end
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