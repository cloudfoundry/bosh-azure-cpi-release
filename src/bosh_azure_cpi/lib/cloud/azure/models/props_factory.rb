# frozen_string_literal: true

module Bosh::AzureCloud
  class PropsFactory
    attr_reader :azure_config

    def initialize(azure_config)
      @azure_config = azure_config
    end

    def parse_vm_props(vm_properties)
      # TODO: add some validation logic here or in the VMCloudProps class.
      Bosh::AzureCloud::VMCloudProps.new(vm_properties, @azure_config)
    end
  end
end
