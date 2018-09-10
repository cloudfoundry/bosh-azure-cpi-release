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
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:snapshot_name) { 'fake-snapshot-name' }
  let(:disk_name) { 'fake-disk-name' }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_managed_snapshot' do
    let(:snapshot_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/#{snapshot_name}?api-version=#{api_version_compute}" }
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:snapshot_params) do
      {
        name: snapshot_name,
        location: 'a',
        tags: {
          snapshot: snapshot_name
        },
        disk_name: disk_name
      }
    end

    let(:disk_response_body) do
      {
        id: 'a',
        name: 'b',
        location: 'c',
        tags: {
          disk: disk_name
        },
        sku: {
          name: 'f'
        },
        properties: {
          provisioningState: 'd',
          diskSizeGB: 'e'
        }
      }
    end

    let(:request_body) do
      {
        location: 'c',
        tags: {
          'snapshot' => snapshot_name
        },
        properties: {
          creationData: {
            createOption: 'Copy',
            sourceUri: "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}"
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
      stub_request(:get, disk_uri).to_return(
        status: 200,
        body: disk_response_body.to_json,
        headers: {}
      )
      stub_request(:put, snapshot_uri).with(body: request_body).to_return(
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
        azure_client.create_managed_snapshot(resource_group, snapshot_params)
      end.not_to raise_error
    end
  end

  describe '#delete_managed_snapshot' do
    let(:snapshot_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/#{snapshot_name}?api-version=#{api_version_compute}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete the managed snapshot without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, snapshot_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client.delete_managed_snapshot(resource_group, snapshot_name)
        end.not_to raise_error
      end
    end
  end

  describe '#get_managed_snapshot_by_name' do
    let(:snapshot_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/#{snapshot_name}?api-version=#{api_version_compute}" }

    context 'when response body is null' do
      it 'should return nil' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, snapshot_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect(
          azure_client.get_managed_snapshot_by_name(resource_group, snapshot_name)
        ).to be_nil
      end
    end

    context 'when response body is not null' do
      let(:snapshot_response_body) do
        {
          'accountType' => 'a',
          'properties' => {
            'osType' => 'b',
            'creationData' => {
              'createOption' => 'c'
            },
            'diskSizeGB' => 100,
            'timeCreated' => 'd',
            'provisioningState' => 'e',
            'diskState' => 'f'
          },
          'type' => 'Microsoft.Compute/snapshots',
          'location' => 'g',
          'tags' => {
            'h' => 'i'
          },
          'id' => 'j',
          'name' => snapshot_name
        }.to_json
      end

      let(:fake_snapshot) do
        {
          id: 'j',
          name: snapshot_name,
          location: 'g',
          tags: { 'h' => 'i' },
          provisioning_state: 'e',
          disk_size: 100
        }
      end

      it 'should return the resource' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, snapshot_uri).to_return(
          status: 200,
          body: snapshot_response_body,
          headers: {}
        )

        expect(
          azure_client.get_managed_snapshot_by_name(resource_group, snapshot_name)
        ).to eq(fake_snapshot)
      end
    end
  end
end
