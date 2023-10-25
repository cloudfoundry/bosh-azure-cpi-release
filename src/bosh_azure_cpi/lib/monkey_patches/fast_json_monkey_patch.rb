# frozen_string_literal: true

# Note this will be removed when xenial with ESM is out of support
# @TODO remove when xenial is no longer supported

module Bosh::AzureCloud
  module FastJsonMonkeyPatch
    def self.apply_patch
      require 'json'
      fast_json_facade = Class.new do
        def self.parse(*args)
          JSON.parse(*args)
        end

        def self.load(*args)
          JSON.load_file(*args)
        end
      end
      Object.const_set(:FastJsonparser, fast_json_facade)
    end
  end
end
