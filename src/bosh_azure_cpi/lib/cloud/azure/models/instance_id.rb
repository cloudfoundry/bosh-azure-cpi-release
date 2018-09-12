# frozen_string_literal: true

module Bosh::AzureCloud
  class InstanceId < ResObjectId
    include Helpers
    # V1 format:
    #   With unmanaged disks: "[STORAGE-ACCOUNT-NAME]-[AGENT-ID]"
    #   With managed disks:   "[AGENT-ID]"
    # V2 format:
    #   With unmanaged disks: "resource_group_name:[RESOURCE-GROUP-NAME];agent_id:[AGENT-ID];storage_account_name:[STORAGE-ACCOUNT-NAME]"
    #   With managed disks:   "resource_group_name:[RESOURCE-GROUP-NAME];agent_id:[AGENT-ID]"
    # Usage:
    #  Creating id for a new VM
    #   instance_id = InstanceId.create(resource_group_name, agent_id, storage_account_name) # Create V2 instance id with unmanaged disks
    #   instance_id = InstanceId.create(resource_group_name, agent_id)                       # Create V2 instance id with managed disks
    #  Paring id for an existing VM
    #   instance_id = InstanceId.parse(id, resource_group_name)

    AGENT_ID_KEY = 'agent_id'
    STORAGE_ACCOUNT_NAME_KEY = 'storage_account_name'
    private_class_method :new

    # Params:
    # - resource_group_name: the resource group name which the instance will be in.
    # - agent_id: the agent id.
    # - storage_account_name: the storage account name.
    def self.create(resource_group_name, agent_id, storage_account_name = nil)
      id_hash = {
        RESOURCE_GROUP_NAME_KEY  => resource_group_name,
        AGENT_ID_KEY             => agent_id
      }
      id_hash[STORAGE_ACCOUNT_NAME_KEY] = storage_account_name unless storage_account_name.nil?
      new(id_hash)
    end

    # Params:
    # - id: the id string
    # - default_resource_group_name: the default resource group name in global config.
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

    def storage_account_name
      unless @plain_id.nil?
        return nil if use_managed_disks?

        return _parse_with_unmanaged_disks_plain(@plain_id)[0]
      end
      @id_hash[STORAGE_ACCOUNT_NAME_KEY]
    end

    def use_managed_disks?
      return @plain_id.length == UUID_LENGTH unless @plain_id.nil?

      @id_hash[STORAGE_ACCOUNT_NAME_KEY].nil?
    end

    def validate
      if !@plain_id.nil?
        invalid = @plain_id.length != UUID_LENGTH && _parse_with_unmanaged_disks_plain(@plain_id)[1].length != UUID_LENGTH
        cloud_error("Invalid instance id (plain) '#{self}'") if invalid
      else
        cloud_error("Invalid resource_group_name in instance id (version 2) '#{self}'") if resource_group_name.nil? || resource_group_name.empty?
        cloud_error("Invalid vm_name in instance id (version 2)' '#{self}'") if vm_name.nil? || vm_name.empty?
        unless storage_account_name.nil?
          cloud_error("Invalid storage_account_name in instance id (version 2) '#{self}'") if storage_account_name.empty?
        end
      end
    end

    private

    # @Return [storage_account_name, agent_id]
    def _parse_with_unmanaged_disks_plain(plain_id)
      ret = plain_id.match('^([^-]*)-(.*)$')
      cloud_error("Invalid instance id (plain) '#{plain_id}'") if ret.nil?
      [ret[1], ret[2]]
    end
  end
end
