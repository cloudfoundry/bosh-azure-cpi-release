module Bosh::AzureCloud
  class VipNetwork < Network
    # {
    #   "vip" => {
    #     "type" => "vip",
    #     "ip"   => "xxx.xxx.xxx.xxx",
    #     "cloud_properties" => {
    #       "resource_group_name" => "rg-name"
    #     }
    #   }
    # }
    def public_ip
      @ip
    end
  end
end
