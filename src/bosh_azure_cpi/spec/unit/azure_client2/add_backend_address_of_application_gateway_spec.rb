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
  let(:resource_group) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  let(:ag_name) { "fake-ag-name" }
  let(:backend_address) { "fake-backend-address" }
  let(:ag) {
    {
      :properties => {
        :backendAddressPools => [
          {
            :properties => {
              :backendAddresses => []
            }
          }
        ]
      }
    }
  }
  let(:ag_after) {
    {
      :properties => {
        :backendAddressPools => [
          {
            :properties => {
              :backendAddresses => [
                {
                  :ipAddress => backend_address
                }
              ]
            }
          }
        ]
      }
    }
  }
  let(:ag_included_target_ip) {
    {
      :properties=> {
        :backendAddressPools => [
          {
            :properties => {
              :backendAddresses => [
                {
                  :ipAddress => backend_address
                }
              ]
            }
          }
        ]
      }
    }
  }
  
  describe "#add address to application gateway backend pool" do

    let(:application_gateway_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/applicationGateways/#{ag_name}?api-version=#{api_version}" }

    context "when token is valid, the ip address is not in the backend pool, create operation is accepted and completed" do
      it "should create a network interface without error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, application_gateway_uri).to_return(
          :status => 200,
          :body => ag.to_json,
          :headers => {})
        stub_request(:put, application_gateway_uri).with(body: ag_after).to_return(
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
          azure_client2.add_backend_address_of_application_gateway(ag_name, backend_address)
        }.not_to raise_error
      end
    end
    
    context "when the ip address is already in the backend pool" do
      it "should not update the application gateway" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, application_gateway_uri).to_return(
          :status => 200,
          :body => ag_included_target_ip.to_json,
          :headers => {})

        expect(Net::HTTP::Put).not_to receive(:new)
        expect {
          azure_client2.add_backend_address_of_application_gateway(ag_name, backend_address)
        }.not_to raise_error
      end
    end
    
    context "when the application gateway is not found" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, application_gateway_uri).to_return(
          :status => 404,
          :body => "",
          :headers => {})

        expect {
          azure_client2.add_backend_address_of_application_gateway(ag_name, backend_address)
        }.to raise_error { |error|
          expect(error.inspect).to match(/AzureNotFoundError/)
        }
      end
    end
  end
end
