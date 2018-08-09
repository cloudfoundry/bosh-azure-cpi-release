# frozen_string_literal: true

module Bosh::AzureCloud
  class DiskId
    include Helpers

    # V1 format:
    #   With unmanaged disks:
    #         data disk:      "bosh-data-[STORAGE-ACCOUNT-NAME]-[UUID]-[CACHING]"
    #         snapshot disk:  "bosh-data-[STORAGE-ACCOUNT-NAME]-[UUID]-[CACHING]--[SNAPSHOTTIME]"
    #   With managed disks:
    #         data disk:      "bosh-disk-data-[AGENTID]-[CACHING]"
    #         snapshot disk:  "bosh-disk-data-[AGENTID]-[CACHING]"
    # V2 format:
    #   With unmanaged disks:
    #         data disk:      "disk_name:bosh-data-[UUID];caching:[CACHING];storage_account_name:[STORAGE-ACCOUNT-NAME]"
    #         snapshot disk:  "disk_name:bosh-data-[UUID]--[SNAPSHOTTIME];caching:[CACHING];storage_account_name:[STORAGE-ACCOUNT-NAME]"
    #   With managed disks:
    #         data disk:      "disk_name:bosh-disk-data-[UUID];caching:[CACHING];resource_group_name:[RESOURCE-GROUP-NAME]"
    #         snapshot disk:  "disk_name:bosh-disk-data-[UUID];caching:[CACHING];storage_account_name:[STORAGE-ACCOUNT-NAME]"
    #
    # Usage:
    #  Creating id for a new disk
    #   disk_id = DiskId.create(caching, false, storage_account_name: 'ss') # Create V2 unmanaged disk id
    #   disk_id = DiskId.create(caching, true, resource_group_name: 'rr')  # Create V2 managed disk id
    #  Parsing id for an existing disk
    #   disk_id = DiskId.parse(id, azure_config)

    CACHING_KEY = 'caching'
    DISK_NAME_KEY = 'disk_name'
    RESOURCE_GROUP_NAME_KEY = 'resource_group_name'
    STORAGE_ACCOUNT_NAME_KEY = 'storage_account_name'

    private_methods :_generate_data_disk_name
    private_class_method :new

    def initialize(obj_id)
      @obj_id = obj_id
    end

    def self.create(caching, use_managed_disks, disk_name: nil, resource_group_name: nil, storage_account_name: nil)
      id_hash = {
        DISK_NAME_KEY => disk_name.nil? ? _generate_data_disk_name(use_managed_disks) : disk_name,
        CACHING_KEY   => caching
      }
      id_hash[RESOURCE_GROUP_NAME_KEY] = resource_group_name unless resource_group_name.nil?
      id_hash[STORAGE_ACCOUNT_NAME_KEY] = storage_account_name unless storage_account_name.nil?
      @obj_id = Bosh::AzureCloud::ObjectId.new(id_hash)
      new(@obj_id)
    end

    def self.parse(id_str, default_resource_group_name)
      @obj_id = Bosh::AzureCloud::ObjectId.parse(
        id_str,
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

    def disk_name
      return @obj_id.plain_id unless @obj_id.plain_id.nil?
      @obj_id.id_hash[DISK_NAME_KEY]
    end

    def caching
      invalid = !disk_name.start_with?(DATA_DISK_PREFIX, MANAGED_DATA_DISK_PREFIX)
      cloud_error('This function should only be called for data disks') if invalid

      return _parse_data_disk_caching_v1(@obj_id.plain_id) unless @obj_id.plain_id.nil?
      @obj_id.id_hash[CACHING_KEY]
    end

    def storage_account_name
      invalid = disk_name.start_with?(MANAGED_DATA_DISK_PREFIX)
      cloud_error('This function should only be called for unmanaged disks') if invalid

      return _parse_storage_account_v1(@obj_id.plain_id) unless @obj_id.plain_id.nil?
      @obj_id.id_hash[STORAGE_ACCOUNT_NAME_KEY]
    end

    def validate
      if @obj_id.plain_id.nil?
        cloud_error("Invalid disk_name in disk id (version 2) '#{@obj_id}'") if disk_name.nil? || disk_name.empty?
        cloud_error("Invalid caching in disk id (version 2) '#{@obj_id}'") if caching.nil? || caching.empty?
        unless resource_group_name.nil?
          cloud_error("Invalid resource_group_name in disk id (version 2) '#{@obj_id}'") if resource_group_name.empty?
        end
        if disk_name.start_with?(DATA_DISK_PREFIX)
          cloud_error("Invalid storage_account_name in disk id (version 2) '#{@obj_id}'") if storage_account_name.nil? || storage_account_name.empty?
        end
      end
    end

    def self._generate_data_disk_name(use_managed_disks)
      "#{use_managed_disks ? MANAGED_DATA_DISK_PREFIX : DATA_DISK_PREFIX}-#{SecureRandom.uuid}"
    end

    private

    def _parse_data_disk_caching_v1(disk_name)
      caching = disk_name.split('-')[-1]
      validate_disk_caching(caching)
      caching
    end

    def _parse_storage_account_v1(disk_name)
      if disk_name.start_with?(DATA_DISK_PREFIX)
        ret = disk_name.match("^#{DATA_DISK_PREFIX}-([^-]*)-(.*)-([^-]*)$")
        cloud_error("Invalid unmanaged data disk name #{disk_name}") if ret.nil?
        ret[1]
      else
        cloud_error("Invalid data disk name (version 1) #{disk_name}")
      end
    end
  end
end
