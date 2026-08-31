# frozen_string_literal: true

module Bosh::AzureCloud
  class DiskId < ResObjectId
    include Helpers
    # V1 format (managed disks):
    #         data disk:      "bosh-disk-data-[AGENTID]-[CACHING]"
    #         snapshot disk:  "bosh-disk-data-[AGENTID]-[CACHING]"
    # V2 format (managed disks):
    #         data disk:      "caching:[CACHING];disk_name:bosh-disk-data-[UUID];resource_group_name:[RESOURCE-GROUP-NAME]"
    #         snapshot disk:  "caching:[CACHING];disk_name:bosh-disk-data-[UUID];resource_group_name:[RESOURCE-GROUP-NAME]"
    #
    # Usage:
    #  Creating id for a new disk
    #   disk_id = DiskId.create(caching, resource_group_name: 'rr')  # Create V2 managed disk id
    #  Parsing id for an existing disk
    #   disk_id = DiskId.parse(id, default_resource_group_name)

    CACHING_KEY = 'caching'
    DISK_NAME_KEY = 'disk_name'

    private_class_method :new

    def self.create(caching, disk_name: nil, resource_group_name: nil)
      id_hash = {
        DISK_NAME_KEY => disk_name.nil? ? _generate_data_disk_name : disk_name,
        CACHING_KEY => caching
      }
      id_hash[RESOURCE_GROUP_NAME_KEY] = resource_group_name unless resource_group_name.nil?
      new(id_hash)
    end

    def self.parse(id_str, default_resource_group_name)
      id_hash, plain_id = ResObjectId.parse_with_resource_group(id_str, default_resource_group_name)
      obj_id = new(id_hash, plain_id)
      obj_id.validate
      obj_id
    end

    def disk_name
      return @plain_id unless @plain_id.nil?

      @id_hash[DISK_NAME_KEY]
    end

    def caching
      return _parse_data_disk_caching_plain(@plain_id) unless @plain_id.nil?

      @id_hash[CACHING_KEY]
    end

    def validate
      if @plain_id.nil?
        cloud_error("Invalid disk_name in disk id (version 2) '#{self}'") if disk_name.nil? || disk_name.empty?
        cloud_error("Invalid caching in disk id (version 2) '#{self}'") if caching.nil? || caching.empty?
        cloud_error("Invalid resource_group_name in disk id (version 2) '#{self}'") if !resource_group_name.nil? && resource_group_name.empty?
      end
    end

    def to_s
      return @plain_id unless @plain_id.nil?

      array = []
      @id_hash.each { |key, value| array << "#{key}:#{value}" }
      array.sort.join(KEY_SEPERATOR)
    end

    private_class_method def self._generate_data_disk_name
      "#{MANAGED_DATA_DISK_PREFIX}-#{SecureRandom.uuid}"
    end

    private

    def _parse_data_disk_caching_plain(disk_name)
      caching = disk_name.split('-')[-1]
      validate_disk_caching(caching)
      caching
    end
  end
end
