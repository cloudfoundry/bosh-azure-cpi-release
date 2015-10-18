module Bosh::AzureCloud
  class Network
    # {
    # "bosh"=>{"netmask"=>nil, "gateway"=>nil, "ip"=>"10.0.0.4", "dns"=>["10.0.0.2"], "type"=>"manual", "default"=>["dns", "gateway"], 
    #          "cloud_properties"=>{"virtual_network_name"=>"abel-boshvnet", "subnet_name"=>"BOSH", "tcp_endpoints"=>["80:80", "443:443", "6868:6868", "25555:25555"]}}, 
    # "vip"=>{"ip"=>"23.101.15.75", "type"=>"vip", 
    #         "cloud_properties"=>{"virtual_network_name"=>"abel-boshvnet", "subnet_name"=>"BOSH", "tcp_endpoints"=>["80:80", "443:443", "6868:6868", "25555:25555"]}}
    #}

    ##
    # Creates a new network
    #
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      unless spec.is_a?(Hash)
        raise ArgumentError, "Invalid spec, Hash expected, " \
                             "#{spec.class} provided"
      end

      @logger = Bosh::Clouds::Config.logger

      @name = name
      @ip = spec["ip"]
      @cloud_properties = spec["cloud_properties"]
      @spec = spec
    end
    
    def cloud_properties
      @cloud_properties
    end
    
    def spec
      @spec
    end
  end
end