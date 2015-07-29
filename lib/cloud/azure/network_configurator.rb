# Copyright (c) 2009-2012 VMware, Inc.

module Bosh::AzureCloud
  ##
  # Represents Azure instance network config. Azure VM has single NIC
  # with dynamic IP address and (optionally) Azure cloud service has a single 
  # reserved IP address which VM is not aware of (vip). 
  #
  class NetworkConfigurator
    include Helpers

    attr_reader :vip_network, :network
    attr_accessor :logger

    ##
    # Creates new network spec
    #
    # @param [Hash] spec raw network spec passed by director
    def initialize(spec)
      unless spec.is_a?(Hash)
        raise ArgumentError, "Invalid spec, Hash expected, " \
                             "#{spec.class} provided"
      end

      @logger = Bosh::Clouds::Config.logger
      @network = nil
      @vip_network = nil

      logger.debug ("networks: #{spec}")
      spec.each_pair do |name, network_spec|
        network_type = network_spec["type"] || "manual"

        case network_type
          when "dynamic"
            cloud_error("Must have exactly one dynamic or manual network per instance") if @network
            @network = DynamicNetwork.new(name, network_spec)

          when "manual"
            cloud_error("Must have exactly one dynamic or manual network per instance") if @network
            @network = ManualNetwork.new(name, network_spec)

          when "vip"
            cloud_error("More than one vip network for '#{name}'") if @vip_network
            @vip_network = VipNetwork.new(name, network_spec)

          else
            cloud_error("Invalid network type '#{network_type}' for Azure, " \
                        "can only handle 'dynamic', 'vip', or 'manual' network types")
        end
      end

      unless @network
        cloud_error("Exactly one dynamic or manual network must be defined")
      end
    end

    def virtual_network_name
      @network.virtual_network_name
    end

    def subnet_name
      @network.subnet_name
    end

    def vnet?
      @network.vnet?
    end

    def private_ip
      (@network.is_a? ManualNetwork) ? @network.private_ip : nil
    end

    def reserved_ip
      @vip_network.reserved_ip unless @vip_network.nil?
    end

    def tcp_endpoints
      parse_endpoints(@vip_network.cloud_properties['tcp_endpoints'])
    end

    def dns
      @network.spec['dns'] if @network.spec.has_key? "dns"
    end

    def udp_endpoints
      parse_endpoints(@vip_network.cloud_properties['udp_endpoints'])
    end

    private

    def parse_endpoints(endpoints)
      return [] if (endpoints.nil?)
      raise ArgumentError, "Invalid 'endpoints', Array expected, " \
                           "#{spec.class} provided" unless endpoints.is_a?(Array)

      endpoint_list = []
      endpoints.each do |endpoint|
        raise "Invalid endpoint '#{endpoint}' given. Format is 'X:Y' where 'X' " \
              "is an internal-facing port between 1 and 65535 and 'Y' is an external-facing " \
              'port in the same range' if !valid_endpoint?(endpoint)
        endpoint_list << endpoint
      end

      return endpoint_list
    end

    def valid_endpoint?(endpoint)
      return false if (endpoint !~ /^\d+:\d+$/)
      endpoint.split(':').each do |port|
        return false if (port.to_i < 0 || port.to_i > 65535)
      end
    end
  end
end
