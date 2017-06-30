require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient2 do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client2) {
    Bosh::AzureCloud::AzureClient2.new(
      mock_cloud_options["properties"]["azure"],
      logger
    )
  }
  let(:subscription_id) { mock_azure_properties['subscription_id'] }
  let(:tenant_id) { mock_azure_properties['tenant_id'] }
  let(:token_api_version) { AZURE_API_VERSION }
  let(:group_api_version) { AZURE_RESOURCE_PROVIDER_GROUP }
  let(:resource_group_name) { 'fake-resource-group-name' }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{token_api_version}" }

  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_resource_group" do
    let(:resource_group_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}?api-version=#{group_api_version}" }

    let(:location) { "fake-location" }

    context "when token is valid, create operation is accepted and completed" do
      context "when it returns 200" do
        it "should create a resource group without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, resource_group_uri).to_return(
            :status => 200,
            :body => '',
            :headers => {
            })

          expect {
            azure_client2.create_resource_group(resource_group_name, location)
          }.not_to raise_error
        end
      end

      context "when it returns 201" do
        it "should create a resource group without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, resource_group_uri).to_return(
            :status => 201,
            :body => '',
            :headers => {
            })

          expect {
            azure_client2.create_resource_group(resource_group_name, location)
          }.not_to raise_error
        end
      end
    end
  end
end
