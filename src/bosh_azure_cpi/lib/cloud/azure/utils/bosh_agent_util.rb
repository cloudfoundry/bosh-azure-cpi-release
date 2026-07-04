# frozen_string_literal: true

module Bosh::AzureCloud
  class BoshAgentUtil
    # Example -
    # For Linux:
    # {
    #   "server": {
    #     "name": "<instance-id>"
    #   },
    #   "dns": {
    #     "nameserver": ["168.63.129.16","8.8.8.8"]
    #   }
    # }
    # For Windows:
    # {
    #   "instance-id": "<instance-id>",
    #   "server": {
    #     "name": "<randomgeneratedname>"
    #   },
    #   "dns": {
    #     "nameserver": ["168.63.129.16","8.8.8.8"]
    #   }
    # }
    #
    def encoded_user_data(instance_id, dns, agent_id, network_spec, environment, vm_params, config, computer_name = nil, nic_groups_to_iface = {})
      user_data = user_data_obj(instance_id, dns, agent_id, network_spec, environment, vm_params, config, computer_name, nic_groups_to_iface)
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def encode_user_data(user_data)
      Base64.strict_encode64(JSON.dump(user_data))
    end

    # Obtain the full VM metadata to write custom data.
    #
    # The agent settings are written directly to the VM's custom data.
    # The stemcell API version is used to determine compatibility with the agent on the stemcell.
    # The agent will read the base metadata, and additionally the agent settings
    def user_data_obj(instance_id, dns, agent_id, network_spec, environment, vm_params, config, computer_name = nil, nic_groups_to_iface = {})
      user_data = { }
      if computer_name
        user_data[:'instance-id'] = instance_id
        user_data[:server] = { name: computer_name }
      else
        user_data[:server] = { name: instance_id }
      end
      user_data[:dns] = { nameserver: dns } if dns

      user_data.merge!(initial_agent_settings(agent_id, network_spec, environment, vm_params, config, nic_groups_to_iface))

      user_data
    end

    def meta_data_obj(instance_id, ssh_public_key)
      user_data_obj = { instance_id: instance_id }
      user_data_obj[:'public-keys'] = {
        '0': {
          'openssh-key': ssh_public_key
        }
      }
      user_data_obj
    end

    # Generates initial agent settings. These settings will be read by agent
    # from the Azure VM's custom data. Disk
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
    def initial_agent_settings(agent_id, network_spec, environment, vm_params, config, nic_groups_to_iface = {})
      settings = {
        'vm' => {
          'name' => vm_params[:name]
        },
        'agent_id' => agent_id,
        'networks' => _agent_network_spec(network_spec, nic_groups_to_iface),
        'disks' => {
          'system' => '/dev/sda',
          'persistent' => {}
        }
      }

      unless vm_params[:ephemeral_disk].nil?
        # Azure uses a data disk as the ephemeral disk and the lun is 0
        settings['disks']['ephemeral'] = {
          'lun' => '0',
          'host_device_id' => Bosh::AzureCloud::Helpers::AZURE_SCSI_HOST_DEVICE_ID
        }
      end

      settings['env'] = environment if environment
      settings.merge(config.agent.to_h)
    end

    private

    # Build agent network spec with DHCP and optional interface alias.
    #
    # When nic_groups_to_iface is provided (dual-stack deployments), networks
    # whose spec contains a 'nic_group' key are annotated with an 'alias' field
    # (e.g. "eth0") so the bosh-agent can map multiple networks to the same OS
    # interface without needing a MAC address (which Azure does not provide at
    # NIC creation time).
    def _agent_network_spec(network_spec, nic_groups_to_iface = {})
      Hash[*network_spec.map do |name, settings|
        settings['use_dhcp'] = true
        nic_group = settings['nic_group']
        if nic_group && nic_groups_to_iface[nic_group]
          settings['alias'] = nic_groups_to_iface[nic_group]
        end
        [name, settings]
      end.flatten]
    end
  end
end
