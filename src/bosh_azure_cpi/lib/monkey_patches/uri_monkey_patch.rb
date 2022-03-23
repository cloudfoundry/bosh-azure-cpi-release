# frozen_string_literal: true

require 'uri'

module Bosh::AzureCloud
  module URIMonkeyPatch
    AZURE_STORAGE_TARGET_VERSION = '2.0.4'

    AZURE_VERSION_MISMATCH_WARNING = "This monkey patch is intended for Azure Storage Table Version #{AZURE_STORAGE_TARGET_VERSION} Please review if the patch is needed in the new version.".freeze

    def self.apply_patch
      raise AZURE_VERSION_MISMATCH_WARNING unless azure_storage_table_version_ok?
      return if ::URI.method_defined?(:escape)

      ::URI.class_eval do
        def self.escape(*args)
          URI.encode_www_form_component(*args)
        end
      end
    end

    def self.azure_storage_table_version_ok?
      Azure::Storage::Table::Version.to_s == AZURE_STORAGE_TARGET_VERSION
    end
  end
end
