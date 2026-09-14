# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AzureClient do
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      Bosh::Clouds::Config.logger
    )
  end

  describe '#update_load_balancer_backend_pool' do
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:load_balancer_name) { 'fake-load-balancer-name' }
    let(:backend_pool_name) { 'fake-backend-pool-name' }
    let(:backend_pool_url) { 'fake-backend-pool-url' }
    let(:backend_addresses) do
      [
        {
          name: 'fake-vm-name',
          properties: {
            ipAddress: '10.0.0.5',
            virtualNetwork: { id: 'fake-vnet-id' }
          }
        }
      ]
    end

    it 'updates the load balancer backend pool addresses' do
      expect(azure_client).to receive(:rest_api_url)
        .with(
          Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_NETWORK,
          Bosh::AzureCloud::AzureClient::REST_API_LOAD_BALANCERS,
          resource_group_name: resource_group_name,
          name: load_balancer_name,
          others: "backendAddressPools/#{backend_pool_name}"
        )
        .and_return(backend_pool_url)
      expect(azure_client).to receive(:http_put)
        .with(
          backend_pool_url,
          { properties: { loadBalancerBackendAddresses: backend_addresses } },
          { 'api-version' => '2025-07-01' }
        )
        .and_return(true)

      result = azure_client.update_load_balancer_backend_pool(
        resource_group_name,
        load_balancer_name,
        backend_pool_name,
        backend_addresses
      )

      expect(result).to be(true)
    end
  end
end