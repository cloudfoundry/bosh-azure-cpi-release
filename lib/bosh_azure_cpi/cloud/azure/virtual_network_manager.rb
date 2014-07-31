require 'bosh/registry/errors'

require_relative 'dynamic_network'

module Bosh::AzureCloud
  class VirtualNetworkManager

    def initialize(vnet_client, affinity_group_manager)
      @vnet_client = vnet_client
      @ag_manager = affinity_group_manager
    end

    # TODO: VIP needs to be re-defined to represent the 'acl' stuff for external-facing vms
    # TODO: Need to support both a single network and multiple networks provided
    # TODO: Need to validate 'cloud_properties' section of 'network_spec'
    def create(network_spec)

      #@logger = Bosh::Clouds::Config.logger

      network_type = network_spec['type'] || 'dynamic'
      case network_type
        when 'dynamic'
          network = DynamicNetwork.new(@vnet_client, network_spec['cloud_properties'])

        when 'vip'
          # For now, will short-circuit with auto-assiged public ip
          network = VipNetwork.new(@vnet_client, network_spec['cloud_properties'])

        else
          raise Bosh::Registry::ConfigError "Invalid network type '#{network_type}' for Azure, " \
                                            "can only handle 'dynamic' or 'vip' network types"
      end

      check_affinity_group(network.affinity_group)
      network.provision
    end


    private

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