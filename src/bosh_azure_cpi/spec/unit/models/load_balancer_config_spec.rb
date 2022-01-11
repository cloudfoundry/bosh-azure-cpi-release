# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::LoadBalancerConfig do
  describe '#to_s' do
    context 'when called' do
      let(:name) { 'fake_name' }
      let(:resource_group_name) { 'fake_rg' }
      let(:backend_pool_name) { 'fake_pool' }
      let(:expected_string) { "name: #{name}, resource_group_name: #{resource_group_name}, backend_pool_name: #{backend_pool_name}" }
      let(:load_balancer_config) { Bosh::AzureCloud::LoadBalancerConfig.new(resource_group_name, name, backend_pool_name) }

      it 'should return the correct string' do
        expect(load_balancer_config.to_s).to eq(expected_string)
      end
    end
  end
end
