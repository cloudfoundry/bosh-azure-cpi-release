# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSInstanceId < ResObjectId
    include Helpers
    include ObjectIDKeys

    # V2 format:
    #   With unmanaged disks: "resource_group_name:[RESOURCE-GROUP-NAME];agent_id:[AGENT-ID];vmss_name:[VMSS-NAME];vmss_instance_id:[VMSS-INSTANCE-id]"
    # Usage:
    #  Creating id for a new VM
    #   instance_id = VMSSInstanceId.create(resource_group_name, agent_id, vmss_name, vmss_instance_id)
    #  Paring id for an existing VM
    #   instance_id = CloudIdParser.parse(id, resource_group_name)

    def self.create(resource_group_name, agent_id, vmss_name, vmss_instance_id)
      id_hash = {
        RESOURCE_GROUP_NAME_KEY => resource_group_name,
        AGENT_ID_KEY => agent_id,
        VMSS_NAME_KEY => vmss_name,
        VMSS_INSTANCE_ID_KEY => vmss_instance_id
      }
      new(id_hash)
    end

    def self.create_from_hash(id_hash, plain_id)
      raise Bosh::Clouds::CloudError, 'do not support plain_id in vmss instance id.' unless plain_id.nil?

      obj_id = new(id_hash, plain_id)
      obj_id.validate
      obj_id
    end

    def vmss_name
      @id_hash[VMSS_NAME_KEY]
    end

    def vmss_instance_id
      @id_hash[VMSS_INSTANCE_ID_KEY]
    end

    def use_managed_disks?
      # we only support the managed disk.
      true
    end

    # TODO: add validate logic for the vmss instance id to the vmss.
    def validate
      true
    end

    def to_s
      super.to_s
    end
  end
end
