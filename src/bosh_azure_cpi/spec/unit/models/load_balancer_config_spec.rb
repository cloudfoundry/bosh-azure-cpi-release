# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::LoadBalancerConfig do
  describe '#to_s' do
    context 'when called' do
      let(:name) { 'fake_name' }
      let(:resource_group_name) { 'fake_rg' }
      let(:backend_pool_name) { 'fake_pool' }
      let(:backend_pool_name_v6) { 'fake_pool_v6' }
      let(:expected_string) { "name: #{name}, resource_group_name: #{resource_group_name}, backend_pool_name: #{backend_pool_name}, backend_pool_name_v6: #{backend_pool_name_v6}" }
      let(:load_balancer_config) do
        Bosh::AzureCloud::LoadBalancerConfig.new(resource_group_name, name, backend_pool_name, backend_pool_name_v6)
      end

      it 'returns the configured IPv6 pool name in its reader and string representation' do
        expect(load_balancer_config.backend_pool_name_v6).to eq(backend_pool_name_v6)
        expect(load_balancer_config.to_s).to eq(expected_string)
      end
    end
  end
end
