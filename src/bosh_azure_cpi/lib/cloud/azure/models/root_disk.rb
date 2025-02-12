# frozen_string_literal: true

module Bosh::AzureCloud
  class RootDisk
    attr_reader :size, :type, :placement, :disk_encryption_set_name

    def initialize(size, type, placement, disk_encryption_set_name: nil)
      @size = size
      @type = type
      @placement = placement
      @disk_encryption_set_name = disk_encryption_set_name
    end
  end
end
