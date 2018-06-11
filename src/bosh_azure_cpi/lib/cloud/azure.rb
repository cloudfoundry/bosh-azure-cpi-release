# frozen_string_literal: true

module Bosh
  module AzureCloud; end
end

require 'date'
require 'pp'
require 'set'
require 'tmpdir'
require 'securerandom'
require 'json'
require 'digest/md5'
require 'base64'
require 'yaml'
require 'time'
require 'socket'
require 'vhd'
require 'open3'
require 'etc'
require 'fcntl'
require 'jwt'
# Use resolv-replace.rb to replace the libc resolver
# Reference:
#  https://makandracards.com/ninjaconcept/30815-fixing-socketerror-getaddrinfo-name-or-service-not-known-with-ruby-s-resolv-replace-rb
#  http://www.subelsky.com/2014/05/fixing-socketerror-getaddrinfo-name-or.html
require 'resolv-replace.rb'
require 'net/http'

# Load Azure Libs before cloud/azure/* in case they are used by the latter
require 'azure/storage'
require 'azure/core/http/debug_filter'

require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'
require 'common/common'

require 'bosh/cpi'
require 'bosh/cpi/registry_client'

require 'cloud'
require 'cloud/azure/helpers'
require 'cloud/azure/cloud'
require 'cloud/azure/azure_client2'

require 'cloud/azure/network'
require 'cloud/azure/manual_network'
require 'cloud/azure/dynamic_network'
require 'cloud/azure/vip_network'
require 'cloud/azure/network_configurator'
require 'cloud/azure/vm_manager'
require 'cloud/azure/blob_manager'
require 'cloud/azure/disk_manager'
require 'cloud/azure/stemcell_manager'
require 'cloud/azure/table_manager'
require 'cloud/azure/light_stemcell_manager'

require 'cloud/azure/disk_manager2'
require 'cloud/azure/stemcell_manager2'
require 'cloud/azure/storage_account_manager'

require 'cloud/azure/instance_id'
require 'cloud/azure/disk_id'

require 'cloud/azure/instance_type_mapper'

require 'cloud/azure/version'
require 'cloud/azure/telemetry/telemetry_manager'
require 'cloud/azure/telemetry/telemetry_event'
require 'cloud/azure/telemetry/telemetry_event_handler'
require 'cloud/azure/telemetry/wire_client'

module Bosh
  module Clouds
    Azure = Bosh::AzureCloud::Cloud
  end
end
