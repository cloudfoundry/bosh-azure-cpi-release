# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient2 do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client2) do
    Bosh::AzureCloud::AzureClient2.new(
      mock_cloud_options['properties']['azure'],
      logger
    )
  end
  let(:subscription_id) { mock_azure_properties['subscription_id'] }
  let(:tenant_id) { mock_azure_properties['tenant_id'] }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:resource_group) { 'fake-resource-group-name' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }

  let(:public_ip_name) { 'fake-public-ip-name' }
  let(:valid_access_token) { 'valid-access-token' }

  let(:expires_on) { (Time.now + 1800).to_i.to_s }

  describe '#delete_public_ip' do
    let(:public_ip_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}?api-version=#{api_version_network}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete a public ip without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, public_ip_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client2.delete_public_ip(resource_group, public_ip_name)
        end.not_to raise_error
      end
    end
  end
end
