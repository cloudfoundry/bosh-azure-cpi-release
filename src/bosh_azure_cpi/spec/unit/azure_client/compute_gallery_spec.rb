# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      logger
    )
  end
  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:resource_group) { mock_azure_config.resource_group_name }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:gallery_name) { 'fake-gallery-name' }
  let(:location) { 'fake-location' }
  let(:image_name) { 'fake-image-name' }

  describe '#create_gallery_image_definition' do
    let(:image_definition_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/#{api_version_compute}/galleries/#{gallery_name}/images/#{image_name}?api-version=2024-07-01" }
    let(:params) do
      {
        'location'  => location,
        'publisher' => 'fake-publisher',
        'offer'     => 'fake-offer',
        'sku'       => 'fake-sku',
        'osType'    => 'Linux',
        'tags'      => { 'foo' => 'bar' }
      }
    end

    before do
      allow(azure_client).to receive(:rest_api_url).and_return(image_definition_uri)
      allow(azure_client).to receive(:http_put)
    end

    context 'when all required parameters are present' do
      it 'creates the gallery image definition without error' do
        expect(azure_client).to receive(:http_put).with(
          image_definition_uri,
          hash_including('location' => location),
          hash_including('api-version' => anything)
        )
        azure_client.create_gallery_image_definition(gallery_name, image_name, params)
      end
    end

    context 'when a required parameter is missing' do
      it 'raises ArgumentError' do
        invalid_params = params.dup
        invalid_params.delete('publisher') # remove a required field
        expect {
          azure_client.create_gallery_image_definition(gallery_name, image_name, invalid_params)
        }.to raise_error(ArgumentError, /Missing required parameter/)
      end
    end
  end

  describe '#create_gallery_image_version' do
    let(:image_version_name) { 'fake-image-version-name' }
    let(:version_uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_name}/versions/#{image_version_name}" }
    let(:tags) { { 'foo' => 'bar' } }
    let(:params) do
      {
        'location'             => location,
        'blob_uri'             => 'fake-blob-uri',
        'storage_account_name' => 'fake-storage-account',
        'tags'                 => tags
      }
    end

    context 'when all required parameters are present' do
      let(:fake_response) do
        {
          "name" => "fake_image",
          "id" => "some-id",
          "location" => location,
          "properties" => {
            "publishingProfile" => {
              "targetRegions" => [{ "name" => location }]
            }
          }
        }
      end
      let(:fake_response_double) { double("response", code: 200, body: fake_response.to_json, headers: {}) }

      before do
        allow(azure_client).to receive(:rest_api_url).and_return(version_uri)
        allow(azure_client).to receive(:http_put).with(version_uri, anything, anything).and_return(fake_response_double)
        allow(azure_client).to receive(:parse_gallery_image).and_call_original
      end

      it 'creates and parses the gallery image version' do
        result = azure_client.create_gallery_image_version(gallery_name, image_name, image_version_name, params)

        expect(azure_client).to have_received(:http_put).with(
          version_uri,
          hash_including('location' => location, 'tags' => tags, 'properties' => {'storageProfile' => anything, 'publishingProfile' => anything}),
          hash_including('api-version' => anything)
        )
        expect(result[:name]).to eq("fake_image")
        expect(result[:id]).to eq("some-id")
        expect(result[:location]).to eq(location)
        expect(result[:target_regions]).to eq([location])
      end
    end

    context 'when required parameter is missing' do
      it 'raises an ArgumentError' do
        invalid_params = params.dup
        invalid_params.delete('location')

        expect {
          azure_client.create_gallery_image_version(gallery_name, image_name, image_version_name, invalid_params)
        }.to raise_error(ArgumentError, /Missing required parameter/)
      end
    end

    context 'when target_regions parameter is provided' do
      let(:params_with_regions) do
        params.merge({
          'target_regions' => ['region1', 'region2']
        })
      end
      let(:fake_response) do
        {
          "name" => "fake_image",
          "id" => "some-id",
          "location" => location,
          "properties" => {
            "publishingProfile" => {
              "targetRegions" => [{ 'name' => 'region1' }, { 'name' => 'region2' }]
            }
          }
        }
      end
      let(:fake_response_double) { double("response", code: 200, body: fake_response.to_json, headers: {}) }

      it 'creates version with multiple target regions' do
        allow(azure_client).to receive(:http_put).and_return(fake_response_double)

        azure_client.create_gallery_image_version(gallery_name, image_name, image_version_name, params_with_regions)

        expect(azure_client).to have_received(:http_put).with(
          version_uri,
          hash_including(
            'properties' => hash_including(
              'publishingProfile' => hash_including(
                'targetRegions' => [
                  { 'name' => 'region1' },
                  { 'name' => 'region2' }
                ]
              )
            )
          ),
          anything
        )
      end
    end

    context 'when replica_count parameter is provided' do
      let(:params_with_replica) do
        params.merge({
          'replica_count' => 3
        })
      end
      let(:fake_response) do
        {
          "name" => "fake_image",
          "id" => "some-id",
          "location" => location,
          "properties" => {
            "publishingProfile" => {
              "targetRegions" => [{ 'name' => 'region1' }, { 'name' => 'region2' }]
            }
          }
        }
      end
      let(:fake_response_double) { double("response", code: 200, body: fake_response.to_json, headers: {}) }

      it 'creates version with specified replica count' do
        allow(azure_client).to receive(:http_put).and_return(fake_response_double)

        azure_client.create_gallery_image_version(gallery_name, image_name, image_version_name, params_with_replica)

        expect(azure_client).to have_received(:http_put).with(
          version_uri,
          hash_including(
            'properties' => hash_including(
              'publishingProfile' => hash_including(
                'replicaCount' => 3
              )
            )
          ),
          anything
        )
      end
    end
  end

  describe '#get_compute_gallery_image_version' do
    let(:version) { 'fake-gallery-image-version' }
    let(:image_definition) { 'fake-image-definition' }

    context 'when the gallery image version exists' do
      let(:fake_result) do
        {
          'name' => version,
          'id' => 'fake-id',
          'location' => 'eastus',
          'properties' => {
            'publishingProfile' => {
              'replicaCount' => 3,
              'targetRegions' => [
                { 'name' => 'eastus' },
                { 'name' => 'westus' }
              ]
            }
          }
        }
      end

      it 'returns the image version details' do
        allow(azure_client).to receive(:get_resource_by_id).and_return(fake_result)

        result = azure_client.get_compute_gallery_image_version(gallery_name, image_definition, version)

        expect(result[:name]).to eq(version)
        expect(result[:id]).to eq('fake-id')
        expect(result[:location]).to eq('eastus')
        expect(result[:target_regions]).to contain_exactly('eastus', 'westus')
      end
    end

    context 'when the gallery image version does not exist' do
      it 'does not raise an error' do
        allow(azure_client).to receive(:get_resource_by_id).and_return(nil)

        expect {
          result = azure_client.get_compute_gallery_image_version(gallery_name, image_definition, version)
          expect(result).to be_nil
        }.not_to raise_error
      end
    end

    context 'when the API returns an error response' do
      it 'raises the error' do
        allow(azure_client).to receive(:get_resource_by_id).and_raise(
          Bosh::AzureCloud::AzureError.new('Failed to get gallery image version')
        )

        expect {
          azure_client.get_compute_gallery_image_version(gallery_name, image_name, version)
        }.to raise_error(Bosh::AzureCloud::AzureError)
      end
    end
  end

  describe '#delete_gallery_image_version' do
    let(:image_version_name) { 'fake-image-version-name' }
    let(:version_uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_name}/versions/#{image_version_name}" }

    context 'when deletion is successful (HTTP 200)' do
      before do
        fake_response = double("response", code: 200, body: "", headers: {})
        allow(azure_client).to receive(:http_delete).with(version_uri, any_args).and_return(fake_response)
      end

      it 'deletes the gallery image version' do
        result = azure_client.delete_gallery_image_version(gallery_name, image_name, image_version_name)
        expect(azure_client).to have_received(:http_delete).with(version_uri, anything) # hash_including('api_version')
        expect(result).to be_truthy
      end
    end

    context 'when deletion fails (e.g., HTTP 404)' do
      before do
        fake_response = double("response", code: 404, body: '{"error": {"message": "Not Found"}}', headers: {})
        allow(azure_client).to receive(:http_delete).with(version_uri, any_args).and_return(fake_response)
      end

      it 'raises no Error' do
        expect {
          azure_client.delete_gallery_image_version(gallery_name, image_name, image_version_name)
        }.not_to raise_error
      end
    end
  end
end
