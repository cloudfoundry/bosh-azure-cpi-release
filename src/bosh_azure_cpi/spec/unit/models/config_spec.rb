# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::Config do
  let(:fake_azure_config) { {} }
  let(:fake_agent_config) { {} }

  describe '#registry_configured?' do
    context 'when registry is configured' do
      let(:config_hash) do
        {
          'registry' => {
            'user' => 'fake_user',
            'password' => 'fake_password',
            'endpoint' => 'fake_endpoint'
          },
          'azure' => fake_azure_config,
          'agent' => fake_agent_config
        }
      end
      let(:config_model) { Bosh::AzureCloud::Config.new(config_hash) }

      it 'should return true' do
        expect(config_model.registry_configured?).to eq(true)
      end
    end

    context 'when registry is not configured' do
      let(:config_hash) do
        {
          # 'registry' => 'fake_registry',
          'azure' => fake_azure_config,
          'agent' => fake_agent_config
        }
      end
      let(:config_model) { Bosh::AzureCloud::Config.new(config_hash) }

      it 'should return false' do
        expect(config_model.registry_configured?).to eq(false)
      end
    end
  end
end
