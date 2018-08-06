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
cpi = Bosh::AzureCloud::Cloud.new(config)

stemcell_id_to_use = nil
if ARGV[0] == '-i'
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
  stemcell_id_to_use = cpi.create_stemcell(ARGV[1], stemcell_properties)
else
  stemcell_id_to_use = ARGV[0]
end

agent_id = SecureRandom.uuid
vm_properties = {
  'instance_type' => 'Standard_D1'
}
i = 0
total_create_cost = 0
total_delete_cost = 0
times = config['azure']['perform_times']
while i < times
  json_str = "{\"private\":{\"cloud_properties\":{\"subnet_name\":\"#{config['azure']['subnet_name']}\",\"virtual_network_name\":\"#{config['azure']['vnet_name']}\"},\"default\":[\"dns\",\"gateway\"],\"dns\":[\"168.63.129.16\",\"8.8.8.8\"],\"gateway\":\"10.0.0.1\",\"ip\":\"10.0.0.42\",\"netmask\":\"255.255.255.0\",\"type\":\"manual\"}}"
  networks = JSON(json_str)
  t1 = Time.now
  puts 'testing create_vm...'
  instance_id = cpi.create_vm(agent_id, stemcell_id_to_use, vm_properties, networks)
  create_cost = (Time.now - t1)
  puts "perf result, create_vm costs #{create_cost}"
  total_create_cost += create_cost

  t1 = Time.now
  puts 'testing delete_vm...'
  cpi.delete_vm(instance_id)
  delete_cost = (Time.now - t1)
  puts "perf result, delete_vm costs #{delete_cost}"
  total_delete_cost += delete_cost
  i += 1
end

puts '############### perf result, ################'
per_item = total_create_cost / times
puts "perf result, mean create_vm cost #{per_item}"
per_item = total_delete_cost / times
puts "perf result, mean delete_vm cost #{per_item}"
