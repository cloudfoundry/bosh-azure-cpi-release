# frozen_string_literal: true

module Bosh::AzureCloud
  class StemcellMeta
    attr_accessor :status
    attr_reader :name, :storage_account_name, :timestamp

    def initialize(name, storage_account_name, status, timestamp = nil)
      @name = name
      @storage_account_name = storage_account_name
      @status = status
      @timestamp = timestamp
    end
  end
end
