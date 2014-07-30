require 'common/common'
require 'time'
require 'socket'
require_relative 'helpers'

module Bosh::AzureCloud
  class InstanceManager
    include Helpers

    def initialize(vm_client, img_client)
      @vm_client = vm_client
      @img_client = img_client
    end

    def create(name, stemcell, uuid, virtual_network, cloud_opts)
      params = {
          :vm_name => "vm-#{name}",
          :vm_user => cloud_opts['user'],
          :password => 'P4$$w0rd!',
          :image => stemcell,
          :location => 'East US'
      }

      opts = {
          # Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only.
          # Error: ConflictError : The storage account named '' is already taken.
          :storage_account_name => "storage#{uuid}",
          :cloud_service_name => "cloud-service-#{uuid}",
          :tcp_endpoints => '80:80,443:443,25555:25555',
          #:private_key_file => cloud_opts['ssh_key_file'] || raise('ssh_key_path must be given to cloud_opts'),
          :certificate_file => cloud_opts['cert_file'] || raise('ssh_cert_path must be given to cloud_opts'),
          :vm_size => cloud_opts[:instance_size] || 'Small',
          :availability_set_name => "avail-set-#{uuid}"
      }

      if (!virtual_network.nil?)

        # TODO: Need to fix stack to handle single network hash, not array of hashes... (oops) [0] accessor is stop-gap
        # As far as I am aware, Azure only supports one virtual network for a vm and it's
        # indicated by name in the API, so I am accepting only the first key (the name of the network)
        opts[:virtual_network_name] = virtual_network[0]['name']
        opts[:subnet_name] = virtual_network[0]['subnets'][0]['name']
      end

      @vm_client.create_virtual_machine(params, opts)
    end

    def find(name, uuid)
      @vm_client.get_virtual_machine(name, "cloud-service-#{uuid}")
    end

    def instance_id
      addr = nil
      Socket.ip_address_list.each do |ip|
        addr = ip.ip_address if (ip.ipv4_private?)
      end

      insts = @img_client.list_virtual_machines.select { |vm| vm.ipaddress == addr }

      # raise an error if something funny happened and we have more than one
      # instance with the same ip or no ip at all
      raise if insts.length != 1

      insts.first.vm_name
    end
  end
end