# frozen_string_literal: true

module Bosh::AzureCloud
  class ConfigFactory
    include Helpers

    def self.build(config_hash)
      ConfigFactory.validate(config_hash)
      Config.new(config_hash)
    end

    def self.validate(config_hash)
      ConfigFactory.validate_options(config_hash)
      ConfigFactory.validate_credentials_source(config_hash)
    end

    def self.validate_options(options)
      # TODO: implement this.
      azure_config_hash = options['azure']
      error_msg = 'azure_stack should be there if environment is AzureStack.'
      raise Bosh::Clouds::CloudError, error_msg if !azure_config_hash.nil? && azure_config_hash['environment'] == ENVIRONMENT_AZURESTACK && azure_config_hash['azure_stack'].nil?
    end

    def self.validate_credentials_source(options)
      # TODO: implement this.
    end
  end
end
