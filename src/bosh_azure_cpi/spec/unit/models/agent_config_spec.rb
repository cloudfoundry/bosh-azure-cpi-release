# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AgentConfig do
  describe '#to_h' do
    context 'when called' do
      let(:agent_hash) do
        { 'k' => 'v' }
      end
      let(:agent_config) { Bosh::AzureCloud::AgentConfig.new(agent_hash) }

      it 'should return the correct value' do
        expect(agent_config.to_h).to eq(agent_hash)
      end
    end
  end
end
