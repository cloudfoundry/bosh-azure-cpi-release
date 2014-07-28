require_relative 'network'

module Bosh::AzureCloud
  class VipNetwork < Network

    def initialize(vnet_client, spec)
      super(vnet_client, spec)
    end
  end
end