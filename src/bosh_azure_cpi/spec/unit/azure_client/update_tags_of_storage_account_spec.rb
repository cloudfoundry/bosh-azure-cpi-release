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
  let(:token_api_version) { AZURE_API_VERSION }
  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{token_api_version}" }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  let(:request_id) { 'fake-request-id' }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:storage_api_version) { AZURE_RESOURCE_PROVIDER_STORAGE }
  let(:storage_account_name) { 'fake-storage-account-name' }
  let(:tags) { { 'foo' => 'bar' } }

  describe '#update_tags_of_storage_account' do
    let(:storage_account_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{MOCK_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}?api-version=#{storage_api_version}" }
    let(:request_body) do
      {
        tags: tags
      }
    end

    before do
      allow(azure_client).to receive(:sleep)
    end

    context 'when everything ok' do
      it 'should update the tags of the storage account' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:patch, storage_account_uri).with(body: request_body).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client.update_tags_of_storage_account(storage_account_name, tags)
        end.not_to raise_error
      end
    end

    context 'when azure async operation failed.' do
      it 'should raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:patch, storage_account_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        stub_request(:get, operation_status_link).to_return(
          status: 200,
          body: '{"status":"Failed"}',
          headers: {
            'Retry-After' => '1'
          }
        )

        expect do
          azure_client.update_tags_of_storage_account(storage_account_name, tags)
        end.to raise_error /check_completion - http code: 200/
      end
    end
  end
end
