require_relative 'network'

module Bosh::AzureCloud
  class DynamicNetwork < Network

    def initialize(vnet_client, spec)
      super(vnet_client, spec)
    end

    def provision
      nil
    end
  end
end