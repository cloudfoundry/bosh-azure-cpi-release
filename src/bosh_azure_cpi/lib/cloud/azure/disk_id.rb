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
    #   disk_id = DiskId.parse(id, azure_properties)

    VERSION1 = 'v1' # class properties: version (string), id (string), default_resource_group_name (string)
    VERSION2 = 'v2' # class properties: version (string), id (json)

    private_class_method :new

    def initialize(version, options = {})
      @version = version
      @id = options[:id]
      @default_resource_group_name = options[:default_resource_group_name]
    end

    def self.create(caching, use_managed_disks, disk_name: nil, resource_group_name: nil, storage_account_name: nil)
      id = {
        'disk_name' => disk_name.nil? ? generate_data_disk_name(use_managed_disks) : disk_name,
        'caching'   => caching
      }
      id['resource_group_name'] = resource_group_name unless resource_group_name.nil?
      id['storage_account_name'] = storage_account_name unless storage_account_name.nil?
      new(VERSION2, id: id)
    end

    def self.parse(id, azure_properties)
      disk_id = nil

      if id.include?(';')
        id_hash = {}
        array = id.split(';')
        array.each do |item|
          ret = item.match('^([^:]*):(.*)$')
          id_hash[ret[1]] = ret[2]
        end
        disk_id = new(VERSION2, id: id_hash, default_resource_group_name: azure_properties['resource_group_name'])
      else
        disk_id = new(VERSION1, id: id, default_resource_group_name: azure_properties['resource_group_name'])
      end

      disk_id.validate
      disk_id
    end

    def self.generate_data_disk_name(use_managed_disks)
      "#{use_managed_disks ? MANAGED_DATA_DISK_PREFIX : DATA_DISK_PREFIX}-#{SecureRandom.uuid}"
    end

    def to_s
      return @id if @version == VERSION1
      array = []
      @id.each { |key, value| array << "#{key}:#{value}" }
      array.sort.join(';')
    end

    def resource_group_name
      return @default_resource_group_name if @version == VERSION1
      @id.fetch('resource_group_name', @default_resource_group_name)
    end

    def disk_name
      return @id if @version == VERSION1
      @id['disk_name']
    end

    def caching
      cloud_error('This function should only be called for data disks') unless disk_name.start_with?(DATA_DISK_PREFIX, MANAGED_DATA_DISK_PREFIX)

      return parse_data_disk_caching_v1(@id) if @version == VERSION1
      @id['caching']
    end

    def storage_account_name
      cloud_error('This function should only be called for unmanaged disks') if disk_name.start_with?(MANAGED_DATA_DISK_PREFIX)

      return parse_storage_account_v1(@id) if @version == VERSION1
      @id['storage_account_name']
    end

    def validate
      if @version == VERSION2
        cloud_error("Invalid disk_name in disk id (version 2) `#{@id}'") if disk_name.nil? || disk_name.empty?
        cloud_error("Invalid caching in disk id (version 2) `#{@id}'") if caching.nil? || caching.empty?
        unless resource_group_name.nil?
          cloud_error("Invalid resource_group_name in disk id (version 2) `#{@id}'") if resource_group_name.empty?
        end
        if disk_name.start_with?(DATA_DISK_PREFIX)
          cloud_error("Invalid storage_account_name in disk id (version 2) `#{@id}'") if storage_account_name.nil? || storage_account_name.empty?
        end
      end
    end

    private

    def parse_data_disk_caching_v1(disk_name)
      caching = disk_name.split('-')[-1]
      validate_disk_caching(caching)
      caching
    end

    def parse_storage_account_v1(disk_name)
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
