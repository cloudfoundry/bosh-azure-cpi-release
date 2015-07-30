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

    ## Encode all values in metadata to string.
    # @param [Hash] metadata
    # @return [Hash]
    def encode_metadata(metadata)
      ret = {}
      metadata.each do |key, value|
        ret[key] = value.to_s
      end
      ret
    end
  end
end
