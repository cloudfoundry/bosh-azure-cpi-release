require 'yaml'

module Bosh::AzureCloud
  module Helpers

    def vm_to_yaml(vm)
      raise 'Invalid vm object returned...' if not(validate(vm))
      { :vm_name => vm.vm_name, :cloud_service_name => vm.cloud_service_name }.to_yaml
    end

    def vm_from_yaml(yaml)
      symbolize_keys(YAML.load(yaml))
    end

    def symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        h
      end
    end

    private

    def validate(vm)
      return (!vm.nil? && !nil_or_empty?(vm.vm_name) && !nil_or_empty?(vm.cloud_service_name))
    end

    def nil_or_empty?(obj)
      return (obj.nil? || obj.empty?)
    end
  end
end