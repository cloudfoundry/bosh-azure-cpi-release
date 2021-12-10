# frozen_string_literal: true

module Bosh::AzureCloud
  class RootDisk
    attr_reader :size, :type

    def initialize(size, type)
      @size = size
      @type = type
    end
  end
end
