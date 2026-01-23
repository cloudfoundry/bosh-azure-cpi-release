# frozen_string_literal: true

module Bosh::AzureCloud
  class SecurityProfile
    include Helpers

    SECURITY_TYPE_KEY       = 'security_type'
    SECURE_BOOT_ENABLED_KEY = 'secure_boot_enabled'

    SUPPORTED_SECURITY_TYPES = [SECURITY_TYPE_TRUSTED_LAUNCH, SECURITY_TYPE_STANDARD].freeze

    VTPM_ENABLED = true

    attr_reader :security_type, :secure_boot_enabled

    def initialize(security_profile_config_hash)
      cloud_error("'security_profile' must be a Hash, but is a #{security_profile_config_hash.class}.") unless security_profile_config_hash.is_a?(Hash)

      @security_type = security_profile_config_hash.fetch(SECURITY_TYPE_KEY, SECURITY_TYPE_TRUSTED_LAUNCH)
      _validate_security_type

      @secure_boot_enabled = security_profile_config_hash.fetch(SECURE_BOOT_ENABLED_KEY, trusted_launch?)
      cloud_error("'#{SECURE_BOOT_ENABLED_KEY}' must be a boolean, but is '#{@secure_boot_enabled.inspect}'.") unless [true, false].include?(@secure_boot_enabled)
      cloud_error("'#{SECURE_BOOT_ENABLED_KEY}' must be false when '#{SECURITY_TYPE_KEY}' is '#{@security_type}'.") if @secure_boot_enabled && !trusted_launch?
    end

    def trusted_launch?
      @security_type == SECURITY_TYPE_TRUSTED_LAUNCH
    end

    def uefi_settings
      return nil unless trusted_launch?

      {
        secure_boot_enabled: @secure_boot_enabled,
        vtpm_enabled: VTPM_ENABLED
      }
    end

    private

    def _validate_security_type
      return if SUPPORTED_SECURITY_TYPES.include?(@security_type)

      if @security_type == SECURITY_TYPE_CONFIDENTIAL_VM
        cloud_error("'#{SECURITY_TYPE_KEY}' '#{SECURITY_TYPE_CONFIDENTIAL_VM}' is not supported by this CPI, yet.")
      end

      cloud_error("Invalid '#{SECURITY_TYPE_KEY}' '#{@security_type}'. Supported values: #{SUPPORTED_SECURITY_TYPES.join(', ')}.")
    end
  end
end
