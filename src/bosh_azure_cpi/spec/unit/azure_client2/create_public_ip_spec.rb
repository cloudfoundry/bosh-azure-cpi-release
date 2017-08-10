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
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:resource_group) { "fake-resource-group-name" }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:public_ip_name) { "fake-public-ip-name" }
  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_public_ip" do
    let(:public_ip_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}?api-version=#{api_version_network}" }

    let(:location) { "fake-location" }

    context "when token is valid, create operation is accepted and completed" do
      context "when creating static public ip" do
        let(:public_ip_params) {
          {
            :name => public_ip_name,
            :location => location,
            :idle_timeout_in_minutes => 4,
            :is_static => true
          }
        }
        let(:fake_public_ip_request_body) {
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Static'
            }
          }
        }

        it "should create a public ip without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_public_ip(resource_group, public_ip_params)
          }.not_to raise_error
        end
      end

      context "when creating dynamic public ip" do
        let(:public_ip_params) {
          {
            :name => public_ip_name,
            :location => location,
            :idle_timeout_in_minutes => 4,
            :is_static => false
          }
        }
        let(:fake_public_ip_request_body) {
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Dynamic'
            }
          }
        }

        it "should create a public ip without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_public_ip(resource_group, public_ip_params)
          }.not_to raise_error
        end
      end

      context "when creating public ip in a zone" do
        let(:public_ip_params) {
          {
            :name => public_ip_name,
            :location => location,
            :idle_timeout_in_minutes => 4,
            :is_static => false,
            :zone => 'fake-zone'
          }
        }
        let(:fake_public_ip_request_body) {
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Dynamic'
            },
            'zones' => ['fake-zone']
          }
        }

        it "should create a public ip without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_public_ip(resource_group, public_ip_params)
          }.not_to raise_error
        end
      end
    end
  end
end
