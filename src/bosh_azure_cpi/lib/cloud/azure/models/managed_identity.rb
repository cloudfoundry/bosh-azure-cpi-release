# frozen_string_literal: true

module Bosh::AzureCloud
  class ManagedIdentity
    include Helpers

    attr_reader :type
    attr_reader :user_assigned_identity_name

    def initialize(managed_identity_config_hash)
      @type = managed_identity_config_hash['type']
      if @type == MANAGED_IDENTITY_TYPE_USER_ASSIGNED
        @user_assigned_identity_name = managed_identity_config_hash['user_assigned_identity_name']
        cloud_error("'user_assign_identity_name' is required when 'type' is '#{MANAGED_IDENTITY_TYPE_USER_ASSIGNED}'") if @user_assigned_identity_name.nil?
      end
    end
  end
end
