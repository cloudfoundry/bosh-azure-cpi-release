# frozen_string_literal: true

module Bosh::AzureCloud
  class CloudIdParser
    include Helpers
    include ObjectIDKeys

    # TODO: the default resource group name concept should not be here.
    # combine all the 'id' logic to save bunch of id parse/create methods.
    def self.parse(id_str, default_resource_group_name)
      id_hash, plain_id = ResObjectId.parse_with_resource_group(id_str, default_resource_group_name)
      if !plain_id.nil?
        if plain_id.start_with?(DATA_DISK_PREFIX, MANAGED_DATA_DISK_PREFIX, MANAGED_CONFIG_DISK_PREFIX)
          DiskId.create_from_hash(id_hash, plain_id)
        else
          # only vm_instance_id have plain_id scenario.
          VMInstanceId.create_from_hash(id_hash, plain_id)
        end
      elsif !id_hash[VMSS_NAME_KEY].nil?
        VMSSInstanceId.create_from_hash(id_hash, plain_id)
      elsif !id_hash[DISK_NAME_KEY].nil?
        DiskId.create_from_hash(id_hash, plain_id)
      else
        VMInstanceId.create_from_hash(id_hash, plain_id)
      end
    end
  end
end
