require_relative 'network'

module Bosh::AzureCloud
  class VipNetwork < Network
    attr_accessor :subnets

    def initialize(vnet_client, spec)
      super(vnet_client, spec)

      @subnets = parse_subnets
    end

    def provision
      @options = {:subnet => @subnets, :dns => @dns_servers}
      @vnet_client.set_network_configuration(@name, @affinity_group, @address_space, @options)
    end

    private

    def parse_subnets
      default_subnet if !spec['subnets']
      subnets = []
      spec['subnets'].each do |subnet|
        subnet['name'] ||= default_name
        subnet['range'] ||= default_cidr

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

    def default_name
      'subnet-1'
    end

    def default_cidr
      '10.0.0.0/8'
    end

    def valid_range?(range)
      range =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/
    end

  end
end