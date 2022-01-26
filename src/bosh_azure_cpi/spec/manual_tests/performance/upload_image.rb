#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'bosh_azure_cpi'
require 'irb'
require 'irb/completion'
require 'ostruct'
require 'optparse'

cloud_config = OpenStruct.new(logger: Logger.new(STDOUT))

Bosh::Clouds::Config.configure(cloud_config)

cpi_config_file = File.expand_path('cpi.cfg', __dir__)
puts cpi_config_file
config = Psych.load_file(cpi_config_file)
cpi = Bosh::AzureCloud::Cloud.new(config, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
stemcell_properties = {
  'name' => 'fake-name2',
  'version' => 'fake-version',
  'infrastructure' => 'azure',
  'hypervisor' => 'hyperv',
  'disk' => '3072',
  'disk_format' => 'vhd',
  'container_format' => 'bare',
  'os_type' => 'linux',
  'os_distro' => 'ubuntu',
  'architecture' => 'x86_64'
}
stemcell_id = cpi.create_stemcell(ARGV[0], stemcell_properties)
puts "####### stemcell id is: #{stemcell_id}"
