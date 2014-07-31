module Bosh
  module AzureCloud; end
end

require "httpclient"
require "pp"
require "set"
require "tmpdir"
require "securerandom"
require "yajl"

require "common/exec"
require "common/thread_pool"
require "common/thread_formatter"

require "bosh/registry/client"

require "cloud"
require "bosh_azure_cpi/cloud/azure/helpers"
require "bosh_azure_cpi/cloud/azure/cloud"
require "bosh_azure_cpi/cloud/azure/version"

require "bosh_azure_cpi/cloud/azure/network_configurator"
require "bosh_azure_cpi/cloud/azure/network"
require "bosh_azure_cpi/cloud/azure/dynamic_network"
#require "bosh_azure_cpi/cloud/azure/stemcell"
require "bosh_azure_cpi/cloud/azure/stemcell_creator"
require "bosh_azure_cpi/cloud/azure/virtual_network_manager"
require "bosh_azure_cpi/cloud/azure/instance_manager"
require "bosh_azure_cpi/cloud/azure/spot_manager"
require "bosh_azure_cpi/cloud/azure/tag_manager"
require "bosh_azure_cpi/cloud/azure/availability_zone_selector"
require "bosh_azure_cpi/cloud/azure/resource_wait"

module Bosh
  module Clouds
    azure = Bosh::AzureCloud::Cloud
  end
end