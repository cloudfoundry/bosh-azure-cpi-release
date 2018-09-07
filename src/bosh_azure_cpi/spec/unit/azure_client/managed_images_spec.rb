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
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { mock_azure_config.resource_group_name }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:image_name) { 'fake-image-name' }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_user_image' do
    let(:image_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/images/#{image_name}?api-version=#{api_version_compute}" }

    let(:image_params) do
      {
        name: image_name,
        location: 'a',
        tags: { 'foo' => 'bar' },
        os_type: 'b',
        source_uri: 'c',
        account_type: 'd'
      }
    end

    let(:request_body) do
      {
        location: 'a',
        tags: {
          foo: 'bar'
        },
        properties: {
          storageProfile: {
            osDisk: {
              osType: 'b',
              blobUri: 'c',
              osState: 'generalized',
              caching: 'readwrite',
              storageAccountType: 'd'
            }
          }
        }
      }
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
      stub_request(:put, image_uri).with(body: request_body).to_return(
        status: 200,
        body: '',
        headers: {
          'azure-asyncoperation' => operation_status_link
        }
      )
      stub_request(:get, operation_status_link).to_return(
        status: 200,
        body: '{"status":"Succeeded"}',
        headers: {}
      )

      expect do
        azure_client.create_user_image(image_params)
      end.not_to raise_error
    end
  end

  describe '#get_user_image_by_name' do
    let(:image_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/images/#{image_name}?api-version=#{api_version_compute}" }

    let(:response_body) do
      {
        id: 'a',
        name: 'b',
        location: 'c',
        tags: {
          foo: 'bar'
        },
        properties: {
          provisioningState: 'd'
        }
      }
    end
    let(:image) do
      {
        id: 'a',
        name: 'b',
        location: 'c',
        tags: {
          'foo' => 'bar'
        },
        provisioning_state: 'd'
      }
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
      stub_request(:get, image_uri).to_return(
        status: 200,
        body: response_body.to_json,
        headers: {}
      )

      expect(
        azure_client.get_user_image_by_name(image_name)
      ).to eq(image)
    end
  end

  describe '#list_user_images' do
    let(:images_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/images?api-version=#{api_version_compute}" }

    let(:response_body) do
      {
        value: [
          {
            id: 'a1',
            name: 'b1',
            location: 'c1',
            tags: {
              foo: 'bar1'
            },
            properties: {
              provisioningState: 'd1'
            }
          },
          {
            id: 'a2',
            name: 'b2',
            location: 'c2',
            tags: {
              foo: 'bar2'
            },
            properties: {
              provisioningState: 'd2'
            }
          }
        ]
      }
    end
    let(:images) do
      [
        {
          id: 'a1',
          name: 'b1',
          location: 'c1',
          tags: {
            'foo' => 'bar1'
          },
          provisioning_state: 'd1'
        },
        {
          id: 'a2',
          name: 'b2',
          location: 'c2',
          tags: {
            'foo' => 'bar2'
          },
          provisioning_state: 'd2'
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
        azure_client.list_user_images
      ).to eq(images)
    end
  end

  describe '#delete_user_image' do
    let(:image_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/images/#{image_name}?api-version=#{api_version_compute}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete the managed image without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, image_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client.delete_user_image(image_name)
        end.not_to raise_error
      end
    end
  end
end
