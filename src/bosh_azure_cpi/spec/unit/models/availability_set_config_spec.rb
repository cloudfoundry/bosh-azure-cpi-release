# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AvailabilitySetConfig do
  describe '#to_s' do
    context 'when called' do
      let(:name) { 'fake_av_set' }
      let(:fault_domain) { 5 }
      let(:update_domain) { 1 }
      let(:availability_set_config) { Bosh::AzureCloud::AvailabilitySetConfig.new(name, update_domain, fault_domain) }
      let(:av_set_string) { "name: #{name}, platform_update_domain_count: #{update_domain} platform_fault_domain_count: #{fault_domain}" }

      it 'should return the correct string' do
        expect(availability_set_config.to_s).to eq(av_set_string)
      end
    end
  end
end
