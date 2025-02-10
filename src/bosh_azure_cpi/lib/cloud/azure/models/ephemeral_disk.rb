# frozen_string_literal: true

module Bosh::AzureCloud
  class EphemeralDisk
    attr_reader :use_root_disk, :size, :type, :caching, :iops, :mbps, :disk_encryption_set_name

    def initialize(use_root_disk, size, type, caching, iops, mbps, disk_encryption_set_name: nil)
      @use_root_disk = use_root_disk
      @size = size
      @type = type
      @caching = caching
      @iops = iops
      @mbps = mbps
      @disk_encryption_set_name = disk_encryption_set_name
    end
  end
end
