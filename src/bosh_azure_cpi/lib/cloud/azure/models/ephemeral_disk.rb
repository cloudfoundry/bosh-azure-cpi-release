# frozen_string_literal: true

module Bosh::AzureCloud
  class EphemeralDisk
    attr_reader :use_root_disk, :size, :type

    def initialize(use_root_disk, size, type)
      @use_root_disk = use_root_disk
      @size = size
      @type = type
    end
  end
end
