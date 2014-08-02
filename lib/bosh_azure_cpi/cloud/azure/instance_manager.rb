require 'common/common'
require 'time'
require 'socket'

module Bosh::AzureCloud
  class InstanceManager
    include Helpers

    def initialize(vm_client, img_client, vnet_client)
      @vm_client = vm_client
      @img_client = img_client
      @vnet_client = vnet_client
    end

    def create(uuid, stemcell, cloud_opts)
      endpoints = '25555:25555'

      params = {
          :vm_name => "vm-#{uuid}",
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

          #:private_key_file => cloud_opts['ssh_key_file'] || raise('ssh_key_path must be given to cloud_opts'),
          :certificate_file => cloud_opts['cert_file'] || raise('ssh_cert_path must be given to cloud_opts'),
          :vm_size => cloud_opts[:instance_size] || 'Small',
          :availability_set_name => "avail-set-#{uuid}"
      }

      if (!dynamic_network.nil?)
        # As far as I am aware, Azure only supports one virtual network for a vm and it's
        # indicated by name in the API, so I am accepting only the first key (the name of the network)
        opts[:virtual_network_name] = dynamic_network.name
        opts[:subnet_name] = dynamic_network.first_subnet['name']
      end

      if (!vip_network.nil?)
        # VIP network just represents the dynamically assigned public ip address azure gives.
        # I am unaware of how to statically assign one
        vip_network.tcp_endpoints.each do |endpoint|
          # Prepend the endpoint followed by a comma
          endpoints = "#{endpoint}, #{endpoints}"
        end
      end

      opts[:tcp_endpoints] = endpoints

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

    private

    def dynamic_network
      @vnet_client.network
    end

    def vip_network
      @vnet_client.vip_network
    end
  end
end