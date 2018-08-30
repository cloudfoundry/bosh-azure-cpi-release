# frozen_string_literal: true

module Bosh::AzureCloud
  class PropsFactory
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def parse_vm_props(vm_properties)
      Bosh::AzureCloud::VMCloudProps.new(vm_properties, @config.azure)
    end
  end
end
