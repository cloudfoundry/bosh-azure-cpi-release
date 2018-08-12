# frozen_string_literal: true

module Bosh::AzureCloud
  class EphemeralDisk
    attr_reader :use_root_disk, :size
    def initialize(use_root_disk, size)
      @use_root_disk = use_root_disk
      @size = size
    end
  end
end
