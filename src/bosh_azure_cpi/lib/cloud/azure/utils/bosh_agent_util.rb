# frozen_string_literal: true

module Bosh::AzureCloud
  class BoshAgentUtil
    include Singleton

    attr_accessor :network_spec, :agent_id, :environment

    # Example -
    # For Linux:
    # {
    #   "registry": {
    #     "endpoint": "http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"
    #   },
    #   "server": {
    #     "name": "<instance-id>"
    #   },
    #   "dns": {
    #     "nameserver": ["168.63.129.16","8.8.8.8"]
    #   }
    # }
    # For Windows:
    # {
    #   "registry": {
    #     "endpoint": "http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"
    #   },
    #   "instance-id": "<instance-id>",
    #   "server": {
    #     "name": "<randomgeneratedname>"
    #   },
    #   "dns": {
    #     "nameserver": ["168.63.129.16","8.8.8.8"]
    #   }
    # }
    def self.get_encoded_user_data(registry_endpoint, instance_id, dns, vm_params, computer_name = nil)
      user_data = get_user_data_obj(registry_endpoint, instance_id, dns, vm_params, computer_name)
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def self.get_user_data_obj(registry_endpoint, instance_id, dns, vm_params, computer_name = nil)
      user_data = { registry: { endpoint: registry_endpoint } }
      if computer_name
        user_data[:'instance-id'] = instance_id
        user_data[:server] = { name: computer_name }
      else
        user_data[:server] = { name: instance_id }
      end
      user_data[:dns] = { nameserver: dns } if dns

      unless Config.instance.use_registry?
        user_data.delete(:registry)
        user_data.merge!(self._agent_user_data(vm_params))
      end

      user_data
    end

    def self.get_meta_data_obj(instance_id, ssh_public_key)
      user_data_obj = { instance_id: instance_id }
      user_data_obj[:'public-keys'] = {
        "0": {
          "openssh-key": ssh_public_key
        }
      }
      user_data_obj
    end

    # Generates initial agent settings. These settings will be read by agent
    # from AZURE registry (also a BOSH component) on a target instance. Disk
    # conventions for Azure are:
    # system disk: /dev/sda
    # ephemeral disk: data disk at lun 0 or nil if use OS disk to store the ephemeral data
    #
    # @param [String] agent_id Agent id (will be picked up by agent to
    #   assume its identity
    # @param [Hash] network_spec Agent network spec
    # @param [Hash] environment
    # @param [Hash] vm_params
    # @return [Hash]
    def self.registry_settings(agent_id, network_spec, environment, vm_params)
      settings = {
          'vm' => {
              'name' => vm_params[:name]
          },
          'agent_id' => agent_id,
          'networks' => _agent_network_spec(network_spec),
          'disks' => {
              'system' => '/dev/sda',
              'persistent' => {}
          }
      }

      unless vm_params[:ephemeral_disk].nil?
        # Azure uses a data disk as the ephermeral disk and the lun is 0
        settings['disks']['ephemeral'] = {
            'lun' => '0',
            'host_device_id' => Bosh::AzureCloud::Helpers::AZURE_SCSI_HOST_DEVICE_ID
        }
      end

      settings['env'] = environment if environment
      settings.merge(Bosh::AzureCloud::Config.instance.agent.to_h)
    end

    def self.prepare_user_data(agent_id, network_spec, environment)
      self.instance.agent_id = agent_id
      self.instance.network_spec = network_spec
      self.instance.environment = environment
    end

    private

    def self._agent_user_data(vm_params)
      self.registry_settings(
          self.instance.agent_id,
          self.instance.network_spec,
          self.instance.environment,
          vm_params
      )
    end

    def self._agent_network_spec(network_spec)
      Hash[*network_spec.map do |name, settings|
        settings['use_dhcp'] = true
        [name, settings]
      end.flatten]
    end

  end
end
