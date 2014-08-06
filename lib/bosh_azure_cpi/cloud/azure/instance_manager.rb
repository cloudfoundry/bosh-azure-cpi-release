require 'common/common'
require 'time'
require 'socket'

require_relative 'dynamic_network'
require_relative 'vip_network'
require_relative 'helpers'

module Bosh::AzureCloud
  class InstanceManager

    include Helpers

    def initialize(vm_client, img_client, vnet_manager)
      @vm_client = vm_client
      @img_client = img_client
      @vnet_manager = vnet_manager
    end

    # TODO: Need a better place to specify instance size than manifest azure properties section
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
        opts[:subnet_name] = dynamic_network.first_subnet[:name]
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

    # TODO: Need to find vms with missing cloud service or with missing name
    def find(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_client.get_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def delete(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_client.delete_virtual_machine(vm_ext[:name], vm_ext[:cloud_service_name])
    end

    def reboot(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_client.restart_virtual_machine(vm_ext[:name], vm_ext[:cloud_service_name])
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

      vm_to_yaml(insts.first)
    end

    def network_spec(vm_id)
      vm = find(vm_id) || raise('Given vm id does not exist')
      d_net = extract_dynamic_network vm
    end

    private

    def dynamic_network
      @vnet_manager.network
    end

    def vip_network
      @vnet_manager.vip_network
    end

    # TODO: Need to figure out how to recreate the 'vlan_name' part of the vip network
    # TODO: Need to return a VipNetwork object
    def extract_vip_network(vm)
      tcp = []
      vm.tcp_endpoints.each do |endpoint|
        next if (endpoint[:name].eql?('SSH')) # SSH is the auto-assigned ssh one from azure and we can ignore it
        tcp << "#{endpoint[:local_port]}:#{endpoint[:public_port]}"
      end
    end

    def extract_dynamic_network(vm)
      return nil if (vm.virtual_network_name.nil?)
      vnet = @vnet_manager.list_virtual_networks.select do |network|
        network.name.eql?(vm.virtual_network_name)
      end.first
      return nil if (vnet.nil?)
      DynamicNetwork.new(@vnet_manager, {
                                          'vlan_name' => vnet.name,
                                          'affinity_group' => vnet.affinity_group,
                                          'address_space' => vnet.address_space,
                                          'dns' => vnet.dns_servers,
                                          'subnets' => vnet.subnets.collect { |subnet|
                                            {
                                                'range' => subnet[:address_prefix],
                                                'name' => subnet[:name]
                                            }
                                        }
      })
    end
  end
end