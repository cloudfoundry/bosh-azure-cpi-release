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
  let(:image_definition) { 'fake-image-name' }
  let(:image_version) { 'fake-image-version-name' }
  let(:stemcell_name) { 'bosh-stemcell-54853dd1-8411-429d-abd0-5a9ebc458951' }

  describe '#create_gallery_image_definition' do
    let(:uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}" }
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

    context 'when all required parameters are present' do
      it 'creates the gallery image definition without error' do
        expect(azure_client).to receive(:http_put).with(
          uri,
          hash_including('location' => location, 'tags' => params['tags'],
          'properties' => hash_including(
            'identifier' => {'publisher' => params['publisher'], 'offer' => params['offer'], 'sku' => params['sku']},
            'osType' => params['osType'],
          )),
          hash_including('api-version' => anything)
        )
        azure_client.create_gallery_image_definition(gallery_name, image_definition, params)
      end
    end

    context 'when a required parameter is missing' do
      it 'raises ArgumentError' do
        invalid_params = params.dup
        invalid_params.delete('publisher') # remove a required field
        expect {
          azure_client.create_gallery_image_definition(gallery_name, image_definition, invalid_params)
        }.to raise_error(ArgumentError, /Missing required parameter/)
      end
    end
  end

  describe '#create_gallery_image_version' do
    let(:uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}" }
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
        allow(azure_client).to receive(:http_put).with(uri, anything, anything).and_return(fake_response_double)
      end

      it 'creates and parses the gallery image version' do
        result = azure_client.create_gallery_image_version(gallery_name, image_definition, image_version, params)

        expect(azure_client).to have_received(:http_put).with(
          uri,
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
          azure_client.create_gallery_image_version(gallery_name, image_definition, image_version, invalid_params)
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

        azure_client.create_gallery_image_version(gallery_name, image_definition, image_version, params_with_regions)

        expect(azure_client).to have_received(:http_put).with(
          uri,
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

        azure_client.create_gallery_image_version(gallery_name, image_definition, image_version, params_with_replica)

        expect(azure_client).to have_received(:http_put).with(
          uri,
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

  describe '#get_gallery_image_version_by_tags' do
    let(:tags) { { 'stemcell-name' => stemcell_name } }
    let(:resource_url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/resources" }
    let(:image_version_url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/jammy/versions/1.651.0" }

    let(:resources_response) do
      {
        'value' => [
          {
            'id' => image_version_url,
            'name' => "#{gallery_name}/jammy/1.651.0",
            'type' => "Microsoft.Compute/galleries/images/versions",
            'tags' => tags,
          }
        ]
      }
    end

    let(:image_versions_response) do
      {
        'name' => '1.651.0',
        'id' => image_version_url,
        'type' => 'Microsoft.Compute/galleries/images/versions',
        'location' => 'eastus',
        'tags' => {
          'stemcell-name' => stemcell_name
        },
        'properties' => {
          'publishingProfile' => {
            'targetRegions' => [
              { 'name' => 'eastus' }
            ],
            'replicaCount' => 1
          }
        }
      }
    end

    let(:expected_result) do
      {
        name: '1.651.0',
        id: image_version_url,
        location: 'eastus',
        gallery_name: gallery_name,
        image_definition: 'jammy',
        tags: {
          'stemcell-name' => stemcell_name
        },
        replica_count: 1,
        target_regions: ['eastus']
      }
    end

    context 'when the gallery image version exists with matching tags' do
      it 'returns the gallery image version' do
        expect(azure_client).to receive(:get_resource_by_id)
          .with(resource_url, hash_including('$filter' => match(/tagName eq 'stemcell-name' and tagValue eq '#{stemcell_name}'/)))
          .and_return(resources_response)
        expect(azure_client).to receive(:get_resource_by_id)
          .with(image_version_url)
          .and_return(image_versions_response)

        result = azure_client.get_gallery_image_version_by_tags(gallery_name, tags)

        expect(result).to eq(expected_result)
      end
    end

    context 'when no image versions match the tags' do
      it 'returns nil' do
        expect(azure_client).to receive(:get_resource_by_id).with(resource_url, anything).and_return(nil)

        result = azure_client.get_gallery_image_version_by_tags(gallery_name, tags)

        expect(result).to be_nil
      end
    end

    context 'when gallery name is nil or empty' do
      it 'returns nil for nil gallery name' do
        result = azure_client.get_gallery_image_version_by_tags(nil, tags)
        expect(result).to be_nil
      end

      it 'returns nil for empty gallery name' do
        result = azure_client.get_gallery_image_version_by_tags('', tags)
        expect(result).to be_nil
      end
    end
  end

  describe '#delete_gallery_image_version' do
    let(:uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}" }

    context 'when deletion is successful (HTTP 200)' do
      before do
        fake_response = double("response", code: 200, body: "", headers: {})
        allow(azure_client).to receive(:http_delete).with(uri, any_args).and_return(fake_response)
      end

      it 'deletes the gallery image version' do
        result = azure_client.delete_gallery_image_version(gallery_name, image_definition, image_version)
        expect(azure_client).to have_received(:http_delete).with(uri)
        expect(result).to be_truthy
      end
    end

    context 'when deletion fails (e.g., HTTP 404)' do
      before do
        fake_response = double("response", code: 404, body: '{"error": {"message": "Not Found"}}', headers: {})
        allow(azure_client).to receive(:http_delete).with(uri, any_args).and_return(fake_response)
      end

      it 'raises no Error' do
        expect {
          azure_client.delete_gallery_image_version(gallery_name, image_definition, image_version)
        }.not_to raise_error
      end
    end
  end
end
