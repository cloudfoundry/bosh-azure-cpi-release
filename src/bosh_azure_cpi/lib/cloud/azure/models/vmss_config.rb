# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSConfig
    attr_reader :availability_zones, :name
    def initialize(name, availability_zones)
      @name = name
      @availability_zones = availability_zones
    end
  end
end
