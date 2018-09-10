# frozen_string_literal: true

module Bosh::AzureCloud
  class BoshAgentUtil
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
    def self.get_encoded_user_data(registry_endpoint, instance_id, dns, computer_name = nil)
      user_data = get_user_data_obj(registry_endpoint, instance_id, dns, computer_name)
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def self.get_user_data_obj(registry_endpoint, instance_id, dns, computer_name = nil)
      user_data = { registry: { endpoint: registry_endpoint } }
      if computer_name
        user_data[:'instance-id'] = instance_id
        user_data[:server] = { name: computer_name }
      else
        user_data[:server] = { name: instance_id }
      end
      user_data[:dns] = { nameserver: dns } if dns
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
  end
end
