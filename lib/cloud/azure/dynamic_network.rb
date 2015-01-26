module Bosh::AzureCloud
  class DynamicNetwork < Network
    attr_accessor :subnets, :address_space, :dns_servers, :affinity_group

    include Helpers
    def initialize(name, spec)
      super
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

    def default_dns
      [{:name => 'google_primary', :ip_address => '8.8.8.8'},
       {:name => 'google_secondary', :ip_address => '8.8.4.4'}]
    end
  end
end