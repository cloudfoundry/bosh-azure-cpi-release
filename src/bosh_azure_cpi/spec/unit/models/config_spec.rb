# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::Config do
  let(:fake_azure_config) { {} }
  let(:fake_agent_config) { {} }

  context 'without a stemcell api provided' do
    let(:config_hash) { mock_cloud_properties_merge({}).tap { |hash| hash['azure'].delete('vm') } }
    let(:config_model) { Bosh::AzureCloud::Config.new(config_hash) }

    it 'defaults to version 2' do
      expect(config_model.azure.stemcell_api_version).to eq(2)
    end
  end

  context 'with a stemcell that does not support api v2' do
    let(:config_hash) { mock_cloud_properties_merge('azure' => { 'vm' => { 'stemcell' => { 'api_version' => 1 } } }) }
    let(:config_model) { Bosh::AzureCloud::Config.new(config_hash) }

    it 'should return raise an error' do
      expect {
        config_model
      }.to raise_error('Stemcell must support api version 2 or higher')
    end
  end
end
