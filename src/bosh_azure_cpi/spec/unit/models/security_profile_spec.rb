# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::SecurityProfile do
  describe '#initialize' do
    context 'when the config is not a Hash' do
      it 'raises an error naming the actual type' do
        expect do
          described_class.new('TrustedLaunch')
        end.to raise_error(Bosh::Clouds::CloudError, /'security_profile' must be a Hash, but is a String/)
      end
    end

    describe 'security_type' do
      it 'defaults to TrustedLaunch' do
        expect(described_class.new({}).security_type).to eq('TrustedLaunch')
      end

      it 'accepts an explicit TrustedLaunch' do
        expect(described_class.new('security_type' => 'TrustedLaunch').security_type).to eq('TrustedLaunch')
      end

      it 'rejects ConfidentialVM' do
        expect do
          described_class.new('security_type' => 'ConfidentialVM')
        end.to raise_error(Bosh::Clouds::CloudError, /'ConfidentialVM' is not supported by this CPI/)
      end

      it 'rejects an unknown value and lists what is supported' do
        expect do
          described_class.new('security_type' => 'Bogus')
        end.to raise_error(Bosh::Clouds::CloudError, /Invalid 'security_type' 'Bogus'\. Supported values: TrustedLaunch, Standard/)
      end

      it 'accepts Standard as an explicit opt out of Trusted Launch' do
        security_profile = described_class.new('security_type' => 'Standard')

        expect(security_profile.security_type).to eq('Standard')
        expect(security_profile.trusted_launch?).to be(false)
      end
    end

    describe 'secure_boot_enabled' do
      it 'defaults to true' do
        expect(described_class.new({}).secure_boot_enabled).to be(true)
      end

      it 'defaults to false for Standard' do
        expect(described_class.new('security_type' => 'Standard').secure_boot_enabled).to be(false)
      end

      it 'can be disabled for custom unsigned kernels or drivers' do
        expect(described_class.new('secure_boot_enabled' => false).secure_boot_enabled).to be(false)
      end

      ['true', 'yes', 1, nil].each do |value|
        it "rejects the non-boolean #{value.inspect}" do
          expect do
            described_class.new('secure_boot_enabled' => value)
          end.to raise_error(Bosh::Clouds::CloudError, /'secure_boot_enabled' must be a boolean/)
        end
      end
    end

    describe 'uefi_settings' do
      it 'always enables vTPM, even when Secure Boot is disabled' do
        expect(described_class.new('secure_boot_enabled' => false).uefi_settings).to eq(
          secure_boot_enabled: false,
          vtpm_enabled: true
        )
      end

      it 'is nil for Standard with Secure Boot explicitly disabled' do
        security_profile = described_class.new(
          'security_type' => 'Standard',
          'secure_boot_enabled' => false
        )

        expect(security_profile.uefi_settings).to be_nil
      end
    end

    describe 'secure_boot_enabled combined with Standard' do
      it 'rejects true because Standard cannot enable Secure Boot' do
        expect do
          described_class.new('security_type' => 'Standard', 'secure_boot_enabled' => true)
        end.to raise_error(Bosh::Clouds::CloudError, /'secure_boot_enabled' must be false when 'security_type' is 'Standard'/)
      end
    end
  end
end
