# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:location) { 'fake-location' }
  let(:publisher) { 'fake-publisher' }
  let(:offer) { 'fake-offer' }
  let(:sku) { 'fake-sku' }

  describe '#list_platform_image_versions' do
    let(:images_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Compute/locations/#{location}/publishers/#{publisher}/artifacttypes/vmimage/offers/#{offer}/skus/#{sku}/versions?api-version=#{api_version_compute}" }

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
