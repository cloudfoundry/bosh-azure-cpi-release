require 'common/common'
require 'time'
require_relative 'helpers'

module Bosh::AzureCloud
  class InstanceManager
    include Helpers

    def initialize(client)
      @client = client
    end

    def create(name, stemcell, uuid, virtual_network, cloud_opts)
      params = {
          :vm_name => "vm_#{name}",
          :vm_user => cloud_opts[:user],
          :password => cloud_opts[:pass],
          :image => stemcell
      }

      opts = {
          :storage_account_name => "storage_#{uuid}",
          :cloud_service_name => "cloud_service_#{uuid}",
          :tcp_endpoints => '22:22,80:80,443:443,25555:25555',
          :private_key_file => cloud_opts[:ssh_key_path] || raise('ssh_key_path must be given to cloud_opts'),
          :certificate_file => cloud_opts[:ssh_cert_path] || raise('ssh_cert_path must be given to cloud_opts'),
          :vm_size => cloud_opts[:instance_size] || 'Small',
          :availability_set_name => "avail_set_#{uuid}"
      }

      if (!virtual_network.nil?)
        virtual_network_name = virtual_network.keys[0] || raise('Missing key name for the network spec.')
        subnet_name = virtual_network.values[0][:subnet_name] || raise('subnet_name is a require parameter for the network spec')

        # As far as I am aware, Azure only supports one virtual network for a vm and it's
        # indicated by name in the API, so I am accepting only the first key (the name of the network)
        opts[:virtual_network_name] = virtual_network_name
        opts[:subnet_name] = subnet_name
      end

      @client.create_virtual_machine(params, opts)
    end
  end
end