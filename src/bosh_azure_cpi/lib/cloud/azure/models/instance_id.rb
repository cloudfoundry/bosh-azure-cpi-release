# frozen_string_literal: true

module Bosh::AzureCloud
  class InstanceId < ResObjectId
    include Helpers
    # V1 format:
    #   "[AGENT-ID]"
    # V2 format:
    #   "resource_group_name:[RESOURCE-GROUP-NAME];agent_id:[AGENT-ID]"
    # Usage:
    #  Creating id for a new VM
    #   instance_id = InstanceId.create(resource_group_name, agent_id)
    #  Parsing id for an existing VM
    #   instance_id = InstanceId.parse(id, resource_group_name)

    AGENT_ID_KEY = 'agent_id'
    private_class_method :new

    def self.create(resource_group_name, agent_id)
      id_hash = {
        RESOURCE_GROUP_NAME_KEY => resource_group_name,
        AGENT_ID_KEY => agent_id
      }
      new(id_hash)
    end

    def self.parse(id_str, default_resource_group_name)
      id_hash, plain_id = ResObjectId.parse_with_resource_group(id_str, default_resource_group_name)
      obj_id = new(id_hash, plain_id)
      obj_id.validate
      obj_id
    end

    def vm_name
      return @plain_id unless @plain_id.nil?

      @id_hash[AGENT_ID_KEY]
    end

    def validate
      if !@plain_id.nil?
        cloud_error("Invalid instance id (plain) '#{self}'") if @plain_id.length != UUID_LENGTH
      else
        cloud_error("Invalid resource_group_name in instance id (version 2) '#{self}'") if resource_group_name.nil? || resource_group_name.empty?
        cloud_error("Invalid vm_name in instance id (version 2)' '#{self}'") if vm_name.nil? || vm_name.empty?
      end
    end
  end
end
