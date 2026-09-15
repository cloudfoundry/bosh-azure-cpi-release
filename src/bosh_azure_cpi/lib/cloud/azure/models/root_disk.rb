# frozen_string_literal: true

module Bosh::AzureCloud
  class RootDisk
    attr_reader :size, :type, :placement, :full_caching, :disk_encryption_set_name

    def initialize(size, type, placement, full_caching: false,disk_encryption_set_name: nil)
      @size = size
      @type = type
      @placement = placement
      @full_caching = full_caching
      @disk_encryption_set_name = disk_encryption_set_name
    end
  end
end
