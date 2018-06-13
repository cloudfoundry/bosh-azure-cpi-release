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
    #
    # Usage:
    #  Creating id for a new VM
    #   instance_id = InstanceId.create(resource_group_name, agent_id, storage_account_name) # Create V2 instance id with unmanaged disks
    #   instance_id = InstanceId.create(resource_group_name, agent_id)                       # Create V2 instance id with managed disks
    #  Paring id for an existing VM
    #   instance_id = InstanceId.parse(id, azure_properties)

    VERSION1 = 'v1' # class properties: version (string), id (string), default_resource_group_name (string)
    VERSION2 = 'v2' # class properties: version (string), id (json)

    private_class_method :new

    def initialize(version, options = {})
      @version = version
      @id = options[:id]

      @default_resource_group_name = options[:default_resource_group_name] if version == VERSION1
    end

    def self.create(resource_group_name, agent_id, storage_account_name = nil)
      id = {
        'resource_group_name'  => resource_group_name,
        'agent_id'             => agent_id
      }
      id['storage_account_name'] = storage_account_name unless storage_account_name.nil?
      new(VERSION2, id: id)
    end

    def self.parse(id, azure_properties)
      instance_id = nil

      if id.include?(';')
        id_hash = {}
        array = id.split(';')
        array.each do |item|
          ret = item.match('^([^:]*):(.*)$')
          id_hash[ret[1]] = ret[2]
        end
        instance_id = new(VERSION2, id: id_hash)
      else
        instance_id = new(VERSION1, id: id, default_resource_group_name: azure_properties['resource_group_name'])
      end

      instance_id.validate
      instance_id
    end

    def to_s
      return @id if @version == VERSION1
      array = []
      @id.each { |key, value| array << "#{key}:#{value}" }
      array.sort.join(';')
    end

    def resource_group_name
      return @default_resource_group_name if @version == VERSION1
      @id['resource_group_name']
    end

    def vm_name
      return @id if @version == VERSION1
      @id['agent_id']
    end

    def storage_account_name
      if @version == VERSION1
        return nil if use_managed_disks?
        return parse_v1_with_unmanaged_disks(@id)[0]
      end
      @id['storage_account_name']
    end

    def use_managed_disks?
      return @id.length == UUID_LENGTH if @version == VERSION1
      @id['storage_account_name'].nil?
    end

    def validate
      if @version == VERSION1
        cloud_error("Invalid instance id (version 1) `#{@id}'") if @id.length != UUID_LENGTH && parse_v1_with_unmanaged_disks(@id)[1].length != UUID_LENGTH
      else
        cloud_error("Invalid resource_group_name in instance id (version 2) `#{@id}'") if resource_group_name.nil? || resource_group_name.empty?
        cloud_error("Invalid vm_name in instance id (version 2)' `#{@id}'") if vm_name.nil? || vm_name.empty?
        unless storage_account_name.nil?
          cloud_error("Invalid storage_account_name in instance id (version 2) `#{@id}'") if storage_account_name.empty?
        end
      end
    end

    private

    # @Return [storage_account_name, agent_id]
    def parse_v1_with_unmanaged_disks(id)
      ret = id.match('^([^-]*)-(.*)$')
      cloud_error("Invalid instance id (version 1) `#{id}'") if ret.nil?
      [ret[1], ret[2]]
    end
  end
end
