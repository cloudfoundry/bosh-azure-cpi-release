module Bosh::AzureCloud
  class VipNetwork < Network
    def public_ip
      @ip
    end
  end
end
