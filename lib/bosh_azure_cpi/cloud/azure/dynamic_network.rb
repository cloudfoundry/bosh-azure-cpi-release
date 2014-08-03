require_relative 'network'

module Bosh::AzureCloud
  class DynamicNetwork < Network
    attr_accessor :subnets, :affinity_group

    include Comparable

    def initialize(vnet_client, spec)
      super(vnet_client, spec)

      @subnets = parse_subnets
      @affinity_group = spec['affinity_group'] || raise("Missing required network property 'affinity_group'")
    end

    def provision
      @options = {:subnet => @subnets, :dns => @dns_servers}
      @vnet_client.set_network_configuration(@name, @affinity_group, @address_space, @options)
    end

    def first_subnet
      @subnets.first
    end

    def <=>(other)
      case other.class.name.split('::').last
        when 'DynamicNetwork'
          return 0

        when 'VipNetwork'
          return 1
      end
    end

    private

    def parse_subnets
      default_subnet if !@spec['subnets']
      subnets = []
      @spec['subnets'].each do |subnet|
        subnet['name'] ||= default_subnet_name
        subnet['range'] ||= default_subnet_cidr

        raise "Invalid range for network '#{subnet[name]}' Must be in CIDR format (x.x.x.x/x)" if not(valid_range?(subnet['range']))
        subnets << {:name => subnet['name'],
                     :ip_address => subnet['range'].split('/')[0],
                     :cidr => subnet['range'].split('/')[1]}
      end
      subnets
    end

    def default_subnet
      [{:name => 'subnet-1',  :ip_address=>'10.0.0.0',  :cidr=>8}]
    end

    def default_subnet_name
      'subnet-1'
    end

    def default_subnet_cidr
      '10.0.0.0/8'
    end

    def valid_range?(range)
      range =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/
    end

  end
end