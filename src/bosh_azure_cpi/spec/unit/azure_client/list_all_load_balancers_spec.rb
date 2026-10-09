# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AzureClient do
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      Bosh::Clouds::Config.logger
    )
  end

  describe '#list_all_load_balancers' do
    let(:load_balancers_url) { 'fake-load-balancers-url' }
    let(:load_balancers) { [{ name: 'fake-load-balancer' }] }

    it 'returns all load balancers from the subscription-level endpoint' do
      expect(azure_client).to receive(:rest_api_url_without_resource_group)
        .with(
          Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_NETWORK,
          Bosh::AzureCloud::AzureClient::REST_API_LOAD_BALANCERS
        )
        .and_return(load_balancers_url)
      expect(azure_client).to receive(:_get_load_balancers)
        .with(load_balancers_url)
        .and_return(load_balancers)

      expect(azure_client.list_all_load_balancers).to eq(load_balancers)
    end

    it 'does not fetch public IPs when listing load balancers' do
      allow(azure_client).to receive(:rest_api_url_without_resource_group).and_return(load_balancers_url)
      allow(azure_client).to receive(:get_resources_by_url).with(load_balancers_url).and_return(
        'value' => [{
          'id' => 'fake-load-balancer-id',
          'name' => 'fake-load-balancer',
          'properties' => {
            'frontendIPConfigurations' => [{
              'name' => 'fake-frontend',
              'id' => 'fake-frontend-id',
              'properties' => { 'publicIPAddress' => { 'id' => 'fake-public-ip-id' } }
            }],
            'backendAddressPools' => []
          }
        }]
      )
      expect(azure_client).not_to receive(:get_public_ip)

      frontend = azure_client.list_all_load_balancers.first[:frontend_ip_configurations].first
      expect(frontend[:name]).to eq('fake-frontend')
      expect(frontend).not_to have_key(:public_ip)
    end
  end
end
