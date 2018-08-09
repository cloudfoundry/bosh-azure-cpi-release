# frozen_string_literal: true

module Bosh::AzureCloud
  class InstanceId
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
    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    STORAGE_ACCOUNT_NAME_KEY = 'storage_account_name'
    private_class_method :new

    def initialize(obj_id)
      @obj_id = obj_id
    end

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
      @obj_id = Bosh::AzureCloud::ObjectId.new(id_hash)
      new(@obj_id)
    end

    # Params:
    # - id: the id string
    # - default_resource_group_name: the default resource group name in global config.
    def self.parse(id, default_resource_group_name)
      @obj_id = Bosh::AzureCloud::ObjectId.parse(
        id,
        RESOURCE_GROUP_NAME_KEY => default_resource_group_name
      )
      instance_id = new(@obj_id)
      instance_id.validate
      instance_id
    end

    def to_s
      @obj_id.to_s
    end

    def resource_group_name
      @obj_id.id_hash[RESOURCE_GROUP_NAME_KEY]
    end

    def vm_name
      return @obj_id.plain_id unless @obj_id.plain_id.nil?
      @obj_id.id_hash[AGENT_ID_KEY]
    end

    def storage_account_name
      unless @obj_id.plain_id.nil?
        return nil if use_managed_disks?
        return _parse_v1_with_unmanaged_disks(@obj_id.plain_id)[0]
      end
      @obj_id.id_hash[STORAGE_ACCOUNT_NAME_KEY]
    end

    def use_managed_disks?
      return @obj_id.plain_id.length == UUID_LENGTH unless @obj_id.plain_id.nil?
      @obj_id.id_hash[STORAGE_ACCOUNT_NAME_KEY].nil?
    end

    def validate
      if !@obj_id.plain_id.nil?
        invalid = @obj_id.plain_id.length != UUID_LENGTH && _parse_v1_with_unmanaged_disks(@obj_id.plain_id)[1].length != UUID_LENGTH
        cloud_error("Invalid instance id (version 1) '#{@obj_id}'") if invalid
      else
        cloud_error("Invalid resource_group_name in instance id (version 2) '#{@obj_id}'") if resource_group_name.nil? || resource_group_name.empty?
        cloud_error("Invalid vm_name in instance id (version 2)' '#{@obj_id}'") if vm_name.nil? || vm_name.empty?
        unless storage_account_name.nil?
          cloud_error("Invalid storage_account_name in instance id (version 2) '#{@obj_id}'") if storage_account_name.empty?
        end
      end
    end

    private

    # @Return [storage_account_name, agent_id]
    def _parse_v1_with_unmanaged_disks(plain_id)
      ret = plain_id.match('^([^-]*)-(.*)$')
      cloud_error("Invalid instance id (version 1) '#{plain_id}'") if ret.nil?
      [ret[1], ret[2]]
    end
  end
end
