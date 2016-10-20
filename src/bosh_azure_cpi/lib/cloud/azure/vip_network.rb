module Bosh::AzureCloud
  class VipNetwork < Network
    def public_ip
      @ip
    end

    def vip?
      true
    end
  end
end
