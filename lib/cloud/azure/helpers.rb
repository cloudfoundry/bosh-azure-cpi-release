module Bosh::AzureCloud
  module Helpers

    AZURE_ENVIRONMENTS = {
      'AzureCloud' => {
        'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254433',
        'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254432',
        'managementEndpointUrl' => 'https://management.core.windows.net',
        'resourceManagerEndpointUrl' => 'https://management.azure.com/',
        'sqlManagementEndpointUrl' => 'https://management.core.windows.net:8443/',
        'sqlServerHostnameSuffix' => '.database.windows.net',
        'galleryEndpointUrl' => 'https://gallery.azure.com/',
        'activeDirectoryEndpointUrl' => 'https://login.windows.net',
        'activeDirectoryResourceId' => 'https://management.core.windows.net/',
        'commonTenantName' => 'common',
        'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
        'activeDirectoryGraphApiVersion' => '2013-04-05'
      },
      'AzureChinaCloud' => {
        'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=301902',
        'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkID=301774',
        'managementEndpointUrl' => 'https://management.core.chinacloudapi.cn',
        'sqlManagementEndpointUrl' => 'https://management.core.chinacloudapi.cn:8443/',
        'sqlServerHostnameSuffix' => '.database.chinacloudapi.cn',
        'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
        'activeDirectoryResourceId' => 'https://management.core.chinacloudapi.cn/',
        'commonTenantName' => 'common',
        'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
        'activeDirectoryGraphApiVersion' => '2013-04-05'
      }
    }

    def generate_instance_id(resource_group_name, agent_id)
      instance_id = "bosh-#{resource_group_name}--#{agent_id}"
    end

    def parse_resource_group_from_instance_id(instance_id)
      index = instance_id.rindex('--') - 1
      instance_id[5..index]
    rescue
      cloud_error("Cannot parse resource group name from instance_id #{instance_id}. The format should be bosh-RESOURCEGROUPNAME--AGENTID")
    end

    ##
    # Raises CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [Exception] exception Exception to be logged (optional)
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    private

    def task_checkpoint
      Bosh::Clouds::Config.task_checkpoint
    end
  end
end
