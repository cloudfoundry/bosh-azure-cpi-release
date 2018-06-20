#!/usr/bin/env ruby
# frozen_string_literal: true

require 'irb'
require 'irb/completion'
require 'ostruct'
require 'optparse'
require 'psych'
require 'git'
require 'fileutils'

test_config_file = File.expand_path('test.cfg', __dir__)
test_config = Psych.load_file(test_config_file)
@additional_rg_name = test_config['additional_rg_name']
@upstream_repo = test_config['upstream_repo']
@test_repo = test_config['test_repo']
@test_branch = test_config['test_branch']
@stemcell_id = test_config['stemcell_id']
@vm_storage_account_name = test_config['vm_storage_account_name']

cpi_config_file = File.expand_path('cpi.cfg', __dir__)
@base_config = Psych.load_file(cpi_config_file)

def checkout_repo(repo, dir: '/tmp/cpi-test', branch: 'master', force_renew: false)
  name = "#{File.basename(repo)}-#{branch}"
  dest_dir = File.join(dir, name)
  return dest_dir if File.exist?(dest_dir) && !force_renew

  FileUtils.rm_rf(dest_dir) if File.exist?(dest_dir)
  Dir.mkdir(dir) unless File.exist?(dir)

  g = Git.clone(repo, name, path: dir)
  g.checkout(branch)
  g.dir.to_s
end

def load_bosh_azure_cpi(cpi_dir, config)
  $LOAD_PATH.unshift File.join(cpi_dir, 'src/bosh_azure_cpi/lib')
  path = File.join(cpi_dir, 'src/bosh_azure_cpi/lib/bosh_azure_cpi.rb')

  Dir[File.join(cpi_dir, 'src/bosh_azure_cpi/lib/**/**/**')]
    .select { |f| File.extname(f) == '.rb' }
    .each { |p| load p }

  $LOAD_PATH.shift

  cloud_config = OpenStruct.new(logger: Logger.new(STDOUT))
  Bosh::Clouds::Config.configure(cloud_config)

  cpi = Bosh::AzureCloud::Cloud.new(config)

  cpi
end

# return instance of cpi
def get_cpi(repo, branch, managed, force_renew: false)
  cpi_dir = checkout_repo(repo, branch: branch, force_renew: force_renew)
  config = @base_config.clone
  config['azure']['use_managed_disks'] = if managed
                                           true
                                         else
                                           false
                                         end

  load_bosh_azure_cpi(cpi_dir, config)
end

def create_vm(cpi, resource_pool)
  stemcell_id = @stemcell_id

  agent_id = SecureRandom.uuid

  networks = JSON('{"private":{"cloud_properties":{"subnet_name":"Bosh","virtual_network_name":"boshvnet-crp"},"default":["dns","gateway"],"dns":["168.63.129.16","8.8.8.8"],"gateway":"10.0.0.1","ip":"10.0.0.57","netmask":"255.255.255.0","type":"manual"}}')

  instance_id = cpi.create_vm(agent_id, stemcell_id, resource_pool, networks)
  check_vm(cpi, instance_id)

  instance_id
end

def delete_vm(cpi, instance_id)
  cpi.delete_vm(instance_id)
end

def check_vm(cpi, instance_id)
  has_vm = cpi.has_vm?(instance_id)
  raise "vm #{instance_id} not found" unless has_vm
  cpi.reboot_vm(instance_id)
  cpi.set_vm_metadata(instance_id, 'key' => 'value')
end

def create_disk(cpi, disk_pool: {}, instance_id: nil)
  disk_id = cpi.create_disk(1024, disk_pool, instance_id)
  check_disk(cpi, disk_id)

  disk_id
end

def check_disk(cpi, disk_id, instance_id: nil)
  has_disk = cpi.has_disk?(disk_id)
  raise "disk #{disk_id} not found" unless has_disk

  unless instance_id.nil?
    disks = cpi.get_disks(instance_id)
    raise "get_disks error - not found #{disk_id} in #{disks}" unless disks.include?(disk_id)
  end
end

def attach_disk(cpi, instance_id, disk_id)
  cpi.attach_disk(instance_id, disk_id)
  check_disk(cpi, disk_id, instance_id: instance_id)
end

def detach_disk(cpi, instance_id, disk_id)
  cpi.detach_disk(instance_id, disk_id)
end

def delete_disk(cpi, disk_id)
  cpi.delete_disk(disk_id)
end

def create_snapshot(cpi, disk_id)
  cpi.snapshot_disk(disk_id)
end

def delete_snapshot(cpi, snapshot_id)
  cpi.snapshot_disk(snapshot_id)
end
