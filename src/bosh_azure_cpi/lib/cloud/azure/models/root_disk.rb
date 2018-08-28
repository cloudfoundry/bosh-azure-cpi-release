# frozen_string_literal: true

module Bosh::AzureCloud
  class RootDisk
    attr_reader :size
    def initialize(size)
      @size = size
    end
  end
end
