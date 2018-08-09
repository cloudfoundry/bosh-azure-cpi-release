# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_cloud_options['properties']['azure'],
      logger
    )
  end
  let(:subscription_id) { mock_azure_config['subscription_id'] }
  let(:tenant_id) { mock_azure_config['tenant_id'] }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { mock_azure_config['resource_group_name'] }
  let(:request_id) { 'fake-request-id' }
  let(:location) { 'fake-location' }
  let(:publisher) { 'fake-publisher' }
  let(:offer) { 'fake-offer' }
  let(:sku) { 'fake-sku' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.now + 1800).to_i.to_s }

  describe '#list_platform_image_versions' do
    let(:images_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/providers/Microsoft.Compute/locations/#{location}/publishers/#{publisher}/artifacttypes/vmimage/offers/#{offer}/skus/#{sku}/versions?api-version=#{api_version_compute}" }

    let(:response_body) do
      [
        {
          id: 'a1',
          name: 'b1',
          location: 'c1'
        },
        {
          id: 'a2',
          name: 'b2',
          location: 'c2'
        }
      ]
    end
    let(:images) do
      [
        {
          id: 'a1',
          name: 'b1',
          location: 'c1'
        },
        {
          id: 'a2',
          name: 'b2',
          location: 'c2'
        }
      ]
    end

    it 'should raise no error' do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
      stub_request(:get, images_uri).to_return(
        status: 200,
        body: response_body.to_json,
        headers: {}
      )

      expect(
        azure_client.list_platform_image_versions(location, publisher, offer, sku)
      ).to eq(images)
    end
  end
end
