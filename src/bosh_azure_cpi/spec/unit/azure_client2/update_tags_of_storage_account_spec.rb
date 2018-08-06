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
  let(:subscription_id) { mock_azure_config['subscription_id'] }
  let(:tenant_id) { mock_azure_config['tenant_id'] }
  let(:token_api_version) { AZURE_API_VERSION }
  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{token_api_version}" }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.now + 1800).to_i.to_s }

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
        azure_client2.update_tags_of_storage_account(storage_account_name, tags)
      end.not_to raise_error
    end
  end
end
