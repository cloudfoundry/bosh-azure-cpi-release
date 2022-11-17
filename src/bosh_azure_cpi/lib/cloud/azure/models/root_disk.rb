# frozen_string_literal: true

module Bosh::AzureCloud
  class RootDisk
    attr_reader :size, :type, :placement

    def initialize(size, type, placement)
      @size = size
      @type = type
      @placement = placement
    end
  end
end
