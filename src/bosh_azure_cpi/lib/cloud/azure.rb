# frozen_string_literal: true

module Bosh
  module AzureCloud; end
end

require 'base64'
require 'concurrent'
require 'date'
require 'etc'
require 'fcntl'
require 'fileutils'
require 'logging'
require 'json'
require 'jwt'
require 'open3'
require 'pp'
require 'set'
require 'securerandom'
require 'socket'
require 'tempfile'
require 'time'
require 'tmpdir'
require 'yaml'

# Use resolv-replace.rb to replace the libc resolver
# Reference:
#  https://makandracards.com/ninjaconcept/30815-fixing-socketerror-getaddrinfo-name-or-service-not-known-with-ruby-s-resolv-replace-rb
#  http://www.subelsky.com/2014/05/fixing-socketerror-getaddrinfo-name-or.html
require 'resolv-replace.rb'

require 'digest/md5'
require 'net/http'
require 'singleton'

# Load Azure Libs before cloud/azure/* in case they are used by the latter
require 'azure/storage/common'
require 'azure/storage/blob'
require 'azure/storage/table'
require 'azure/core/http/debug_filter'

require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'
require 'common/common'

require 'bosh/cpi'
require 'bosh/cpi/registry_client'

require 'cloud'
require 'cloud/azure/utils/helpers'
require 'cloud/azure/utils/bosh_agent_util'
require 'cloud/azure/logging/logger'
require 'cloud/azure/models/bosh_vm_meta'
require 'cloud/azure/utils/command_runner'
require 'cloud/azure/models/error_msg'
require 'cloud/azure/models/object_id_keys'
require 'cloud/azure/models/config'
require 'cloud/azure/models/object_id'
require 'cloud/azure/models/res_object_id'
require 'cloud/azure/models/disk_id'
require 'cloud/azure/models/ephemeral_disk'
require 'cloud/azure/models/vm_instance_id'
require 'cloud/azure/models/vmss_instance_id'
require 'cloud/azure/models/props_factory'
require 'cloud/azure/models/root_disk'
require 'cloud/azure/models/security_group'
require 'cloud/azure/models/managed_identity'
require 'cloud/azure/models/vm_cloud_props'
require 'cloud/azure/models/cloud_id_parser'
require 'cloud/azure/models/vmss_config'
require 'cloud/azure/cloud'
require 'cloud/azure/restapi/rest_helpers'
require 'cloud/azure/restapi/azure_client'
require 'cloud/azure/restapi/azure_client_param_builder'
require 'cloud/azure/restapi/vmss_rest'

require 'cloud/azure/network/network'
require 'cloud/azure/network/manual_network'
require 'cloud/azure/network/dynamic_network'
require 'cloud/azure/network/vip_network'
require 'cloud/azure/network/network_configurator'
require 'cloud/azure/vms/vm_manager_base'
require 'cloud/azure/vms/vmss_manager'
require 'cloud/azure/vms/vm_manager_availability_set'
require 'cloud/azure/vms/vm_manager_network'
require 'cloud/azure/vms/vm_manager'
require 'cloud/azure/disk/vhd_utils'
require 'cloud/azure/vms/vm_manager_adaptive'
require 'cloud/azure/storage/blob_manager'
require 'cloud/azure/disk/disk_manager'
require 'cloud/azure/disk/config_disk_manager'
require 'cloud/azure/stemcell/stemcell_manager'
require 'cloud/azure/meta_store/meta_store'
require 'cloud/azure/meta_store/stemcell_meta'
require 'cloud/azure/meta_store/table_manager'
require 'cloud/azure/stemcell/light_stemcell_manager'

require 'cloud/azure/disk/disk_manager2'
require 'cloud/azure/stemcell/stemcell_manager2'
require 'cloud/azure/storage/storage_account_manager'

require 'cloud/azure/vms/instance_type_mapper'

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
