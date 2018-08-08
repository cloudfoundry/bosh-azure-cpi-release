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
  let(:token_api_version) { AZURE_API_VERSION }
  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{token_api_version}" }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.now + 1800).to_i.to_s }

  let(:storage_api_version) { AZURE_RESOURCE_PROVIDER_STORAGE }
  let(:storage_account_name) { 'fake-storage-account-name' }

  describe '#check_storage_account_name_availability' do
    let(:check_name_availability_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/providers/Microsoft.Storage/checkNameAvailability?api-version=#{storage_api_version}" }
    let(:request_body) do
      {
        name: storage_account_name,
        type: 'Microsoft.Storage/storageAccounts'
      }
    end

    context 'when the response is not nil' do
      it 'should return the availability of the storage account' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, check_name_availability_uri).with(body: request_body).to_return(
          status: 200,
          body: {
            'nameAvailable' => false,
            'reason' => 'AccountNameInvalid',
            'message' => 'fake-message'
          }.to_json,
          headers: {}
        )

        expect(
          azure_client.check_storage_account_name_availability(storage_account_name)
        ).to eq(
          available: false,
          reason: 'AccountNameInvalid',
          message: 'fake-message'
        )
      end
    end

    context 'when the response is nil' do
      it 'should raise an error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, check_name_availability_uri).with(body: request_body).to_return(
          status: 200,
          body: nil,
          headers: {}
        )

        expect do
          azure_client.check_storage_account_name_availability(storage_account_name)
        end.to raise_error(/Cannot check the availability of the storage account name '#{storage_account_name}'/)
      end
    end
  end
end
