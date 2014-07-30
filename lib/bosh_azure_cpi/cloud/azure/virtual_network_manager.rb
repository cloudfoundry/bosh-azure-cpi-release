require 'bosh/clouds/config'
require 'bosh/registry/errors'


require_relative 'dynamic_network'
require_relative 'vip_network'

module Bosh::AzureCloud
  class VirtualNetworkManager

    def initialize(vnet_client, affinity_group_manager)
      @vnet_client = vnet_client
      @ag_manager = affinity_group_manager
    end

    # TODO: Dynamic needs to be re-defined to represent the 'acl' stuff for external-facing vms
    def create(network_spec)

      @logger = Bosh::Clouds::Config.logger

      network_type = network_spec['type'] || 'dynamic'
      case network_type
        when 'dynamic'
          # For now, will short-circuit with auto-assiged public ip
          network = DynamicNetwork.new(@vnet_client, spec)

        when 'vip'
          network = VipNetwork.new(@vnet_client, spec)

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