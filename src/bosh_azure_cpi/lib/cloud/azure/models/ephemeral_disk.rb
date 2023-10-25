# frozen_string_literal: true

module Bosh::AzureCloud
  class EphemeralDisk
    attr_reader :use_root_disk, :size, :type, :caching, :iops, :mbps

    def initialize(use_root_disk, size, type, caching, iops, mbps)
      @use_root_disk = use_root_disk
      @size = size
      @type = type
      @caching = caching
      @iops = iops
      @mbps = mbps
    end
  end
end
