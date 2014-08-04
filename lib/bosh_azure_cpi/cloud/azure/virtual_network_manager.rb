require 'bosh/registry/errors'

require_relative 'dynamic_network'
require_relative 'vip_network'

module Bosh::AzureCloud
  class VirtualNetworkManager
    attr_accessor :network, :vip_network

    def initialize(vnet_client, affinity_group_manager)
      @vnet_client = vnet_client
      @ag_manager = affinity_group_manager
    end

    # TODO: VIP needs to be re-defined to represent the 'acl' stuff for external-facing vms
    # TODO: Need to support both a single network and multiple networks provided
    # TODO: Need to validate 'cloud_properties' section of 'network_spec'
    def create(network_spec)

      #@logger = Bosh::Clouds::Config.logger
      # Need to reset between each call so that this class is stateless between jobs
      @network = nil
      @vip_network = nil

      networks = []
      network_spec.each do |spec|
        #raise Bosh::Registry::ConfigError "'#{spec['type']}' network spec provided is invalid"
        network_type = spec['type'] || 'dynamic'
        case network_type
          when 'dynamic'
            next if (@network)
            @network = DynamicNetwork.new(@vnet_client, spec['cloud_properties'])
            check_affinity_group(@network.affinity_group)
            networks << @network

          when 'vip'
            next if (@vip_network)
            @vip_network = VipNetwork.new(@vnet_client, spec['cloud_properties'])
            networks << @vip_network

          else
            raise Bosh::Registry::ConfigError "Invalid network type '#{network_type}' for Azure, " \
                                              "can only handle 'dynamic' or 'vip' network types"
        end

        # Create the network(s) if they dont exist
        networks.each do |network|
          network.provision
        end
      end
    end

    def parse(network_spec)
      # Need to reset between each call so that this class is stateless between jobs
      temp_network = nil
      temp_vip_network = nil

      networks = []
      network_spec.each do |spec|
        #raise Bosh::Registry::ConfigError "'#{spec['type']}' network spec provided is invalid"
        network_type = spec['type'] || 'dynamic'
        case network_type
          when 'dynamic'
            next if (temp_network)
            temp_network = DynamicNetwork.new(@vnet_client, spec['cloud_properties'])
            #check_affinity_group(temp_network.affinity_group)
            networks << temp_network

          when 'vip'
            next if (temp_vip_network)
            temp_vip_network = VipNetwork.new(@vnet_client, spec['cloud_properties'])
            networks << temp_vip_network

          else
            raise Bosh::Registry::ConfigError "Invalid network type '#{network_type}' for Azure, " \
                                              "can only handle 'dynamic' or 'vip' network types"
        end
      end
      networks.sort_by { |n| [ n.class.name.split('::').last, n.name ] }
    end


    private

    def validate_spec(spec)
      spec.each do |key, value|
        return false if (value.nil? || value == '')
      end
      return true
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