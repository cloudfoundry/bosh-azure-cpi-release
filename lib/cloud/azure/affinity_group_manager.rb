require 'base64'

module Bosh::AzureCloud
  class AffinityGroupManager

    def initialize(base_client)
      @base_client = base_client
    end

    def exist?(name)
      @base_client.list_affinity_groups.each do |ag|
        return true if ag.name.eql?(name)
      end
      return false
    end

    def create(name)
      @base_client.create_affinity_group(name, 'East US', Base64.encode64('BOSH created AG'), {:description => 'Created by BOSH'})
    end
  end
end