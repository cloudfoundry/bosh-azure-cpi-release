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

  describe '#create_update_gallery_image_version' do
    let(:uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}" }
    let(:tags) { { 'foo' => 'bar' } }
    let(:params) { { 'location' => location } }

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
        result = azure_client.create_update_gallery_image_version(gallery_name, image_definition, image_version, params)

        expect(azure_client).to have_received(:http_put).with(
          uri,
          hash_including('location' => location),
          hash_including('api-version' => anything)
        )
        expect(result[:name]).to eq("fake_image")
        expect(result[:id]).to eq("some-id")
        expect(result[:location]).to eq(location)
        expect(result[:target_regions]).to eq([location])
      end

      it 'uses storageAccountId instead of deprecated id property' do
        storage_account_name='fake-storage-account'
        blob_uri='https://fake-storage-account.blob.core.windows.net/container/blob.vhd'
        params_with_blob = params.merge({
          'blob_uri' => blob_uri,
          'storage_account_name' => storage_account_name
        })
        azure_client.create_update_gallery_image_version(gallery_name, image_definition, image_version, params_with_blob)

        expect(azure_client).to have_received(:http_put) do |_uri, request_body, _headers|
          storage_profile = request_body.dig('properties', 'storageProfile', 'osDiskImage', 'source')
          expect(storage_profile).to have_key('storageAccountId')
          expect(storage_profile).not_to have_key('id')
          expect(storage_profile['storageAccountId']).to eq("/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}")
        end
      end
    end

    context 'when required parameter is missing' do
      it 'raises an ArgumentError' do
        invalid_params = params.dup
        invalid_params.delete('location')

        expect {
          azure_client.create_update_gallery_image_version(gallery_name, image_definition, image_version, invalid_params)
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

        azure_client.create_update_gallery_image_version(gallery_name, image_definition, image_version, params_with_regions)

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

        azure_client.create_update_gallery_image_version(gallery_name, image_definition, image_version, params_with_replica)

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

  describe '#get_gallery_image_version_by_stemcell_name' do
    let(:mock_response) { double('response') }
    let(:mock_image_version) { double('image_version') }

    it 'returns nil when gallery name is nil' do
      result = azure_client.get_gallery_image_version_by_stemcell_name(nil, stemcell_name)
      expect(result).to be_nil
    end

    it 'returns nil when gallery name is empty' do
      result = azure_client.get_gallery_image_version_by_stemcell_name('', stemcell_name)
      expect(result).to be_nil
    end

    context 'when API returns nil or empty response' do
      it 'returns nil when get_resource_by_id returns nil' do
        allow(azure_client).to receive(:get_resource_by_id).and_return(nil)
        result = azure_client.get_gallery_image_version_by_stemcell_name(gallery_name, stemcell_name)
        expect(result).to be_nil
      end

      it 'returns nil when response has no value' do
        allow(azure_client).to receive(:get_resource_by_id).and_return({'value' => nil})
        result = azure_client.get_gallery_image_version_by_stemcell_name(gallery_name, stemcell_name)
        expect(result).to be_nil
      end
    end

    context 'when stemcell name matches in stemcell_name tag' do
      it 'returns the matching image version' do
        matching_resource = {
          'id' => "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/test-image/versions/1.0.0",
          'type' => 'Microsoft.Compute/galleries/images/versions',
          'tags' => { 'stemcell_name' => stemcell_name }
        }
        allow(azure_client).to receive(:get_resource_by_id).and_return({'value' => [matching_resource]})
        allow(azure_client).to receive(:get_resource_by_id).with(matching_resource['id']).and_return(mock_image_version)
        allow(azure_client).to receive(:parse_gallery_image).with(mock_image_version).and_return('parsed_result')

        result = azure_client.get_gallery_image_version_by_stemcell_name(gallery_name, stemcell_name)
        expect(result).to eq('parsed_result')
      end
    end

    context 'when stemcell name matches in stemcell_references tag' do
      it 'returns the matching image version when stemcell is in comma-separated list' do
        matching_resource = {
          'id' => "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/test-image/versions/1.0.0",
          'type' => 'Microsoft.Compute/galleries/images/versions',
          'tags' => { 'stemcell_references' => "other-stemcell,#{stemcell_name},another-stemcell" }
        }
        allow(azure_client).to receive(:get_resource_by_id).and_return({'value' => [matching_resource]})
        allow(azure_client).to receive(:get_resource_by_id).with(matching_resource['id']).and_return(mock_image_version)
        allow(azure_client).to receive(:parse_gallery_image).with(mock_image_version).and_return('parsed_result')

        result = azure_client.get_gallery_image_version_by_stemcell_name(gallery_name, stemcell_name)
        expect(result).to eq('parsed_result')
      end
    end

    context 'when no resources match the stemcell name' do
      it 'returns nil when no matching resources are found' do
        non_matching_resource = {
          'id' => "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/test-image/versions/1.0.0",
          'type' => 'Microsoft.Compute/galleries/images/versions',
          'tags' => { 'stemcell_name' => 'different-stemcell' }
        }
        allow(azure_client).to receive(:get_resource_by_id).and_return({'value' => [non_matching_resource]})

        result = azure_client.get_gallery_image_version_by_stemcell_name(gallery_name, stemcell_name)
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

  describe '#get_gallery_image_version' do
    let(:uri) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}" }

    context 'when gallery image version exists' do
      let(:fake_response_body) do
        {
          'id' => "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}",
          'name' => image_version,
          'type' => 'Microsoft.Compute/galleries/images/versions',
          'location' => location,
          'tags' => {
            'stemcell_name' => stemcell_name,
            'image_sha256' => 'fake-sha256-checksum',
            'version' => '1.0'
          },
          'properties' => {
            'provisioningState' => 'Succeeded',
            'publishingProfile' => {
              'targetRegions' => [
                {
                  'name' => location,
                  'regionalReplicaCount' => 3
                }
              ],
              'replicaCount' => 3
            }
          }
        }
      end

      before do
        allow(azure_client).to receive(:get_resource_by_id).with(uri).and_return(fake_response_body)
      end

      it 'returns the parsed gallery image version' do
        expect(azure_client).to receive(:rest_api_url)
          .with('Microsoft.Compute', "galleries/#{gallery_name}/images/#{image_definition}/versions/#{image_version}", resource_group_name: resource_group)
          .and_return(uri)

        result = azure_client.get_gallery_image_version(gallery_name, image_definition, image_version)

        expect(azure_client).to have_received(:get_resource_by_id).with(uri)
        expect(result).not_to be_nil
        expect(result[:id]).to eq(fake_response_body['id'])
        expect(result[:name]).to eq(image_version)
        expect(result[:gallery_name]).to eq(gallery_name)
        expect(result[:image_definition]).to eq(image_definition)
        expect(result[:location]).to eq(location)
        expect(result[:tags]).to eq(fake_response_body['tags'])
        expect(result[:target_regions]).to eq([location])
        expect(result[:replica_count]).to eq(3)
      end
    end

    context 'when gallery image version does not exist' do
      before do
        allow(azure_client).to receive(:get_resource_by_id).with(uri).and_return(nil)
      end

      it 'returns nil' do
        result = azure_client.get_gallery_image_version(gallery_name, image_definition, image_version)
        expect(result).to be_nil
      end
    end

    context 'when API returns an error' do
      before do
        allow(azure_client).to receive(:get_resource_by_id).with(uri).and_raise(StandardError, 'API Error')
      end

      it 'propagates the error' do
        expect {
          azure_client.get_gallery_image_version(gallery_name, image_definition, image_version)
        }.to raise_error(StandardError, 'API Error')
      end
    end
  end
end
