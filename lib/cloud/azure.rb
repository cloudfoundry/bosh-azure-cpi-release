module Bosh
  module AzureCloud; end
end

require 'date'
require 'httpclient'
require 'pp'
require 'set'
require 'tmpdir'
require 'securerandom'
require 'yajl'
require 'digest/md5'
require 'nokogiri'
require 'base64'
require 'yaml'
require 'net/https'
require 'uri'
require 'time'
require 'socket'
require 'vhd'
require 'thread'
require 'open3'

require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'
require 'common/common'

require 'bosh/registry/client'

require 'cloud'
require 'cloud/azure/helpers'
require 'cloud/azure/cloud'
require 'cloud/azure/version'
require 'cloud/azure/azure_client'

require 'cloud/azure/affinity_group_manager'
require 'cloud/azure/network'
require 'cloud/azure/manual_network'
require 'cloud/azure/dynamic_network'
require 'cloud/azure/vip_network'
require 'cloud/azure/network_configurator'
require 'cloud/azure/vm_manager'
require 'cloud/azure/blob_manager'
require 'cloud/azure/disk_manager'
require 'cloud/azure/stemcell_manager'
require 'cloud/azure/storage_account_manager'
require 'cloud/azure/reserved_ip_manager'

require 'azure'

module Bosh
  module Clouds
    Azure = Bosh::AzureCloud::Cloud
  end
end