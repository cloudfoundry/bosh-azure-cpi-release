module Bosh::AzureCloud
  class AffinityGroupManager

    AFFINITY_GROUP_LABEL = 'bosh'
    
    def initialize
      @base_management_service = Azure::BaseManagementService.new
    end

    def exist?(name)
      @base_management_service.list_affinity_groups.each do |ag|
        return true if ag.name.eql?(name)
      end
      return false
    end

    def create(name, location)
      @base_management_service.create_affinity_group(name, location, AFFINITY_GROUP_LABEL, {:description => 'Created by BOSH'})
    end

    def get_affinity_group(name)
      @base_management_service.get_affinity_group(name)
    end
  end
end