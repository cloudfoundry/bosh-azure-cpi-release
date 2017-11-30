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

  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#list_network_interfaces_by_keyword" do
    let(:network_interfaces_url) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces?api-version=#{api_version_network}" }
    let(:instance_id) { "fake-instance-id" }

    context "when network interfaces are not found" do
      let(:result) { { "value" => [] }.to_json }
      it "should return an empty array of network interfaces" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, network_interfaces_url).to_return(
          :status => 200,
          :body => result,
          :headers => {
          })
        expect(
          azure_client2.list_network_interfaces_by_keyword(resource_group, instance_id)
        ).to eq([])
      end
    end

    context "when network interfaces are found and some of them have the keyword in the name" do
      let(:result) {
        {
          "value" => [
            {
              "name"  => "#{instance_id}-0",
              "id"  => "a",
              "location"  => "b",
              "tags"  => {},
              "properties"  => {
                "provisioningState"  => "c",
                "ipConfigurations"  => [
                  {
                    "id"  => "d0",
                    "properties"  => {
                      "privateIPAddress"  => "e0",
                      "privateIPAllocationMethod"  => "f0"
                    }
                  }
                ],
                "dnsSettings"  => {
                   "dnsServers"  => [
                      "g",
                      "h"
                   ]
                }
              }
            },
            {
              "name"  => "#{instance_id}-1",
              "id"  => "a",
              "location"  => "b",
              "tags"  => {},
              "properties"  => {
                "provisioningState"  => "c",
                "ipConfigurations"  => [
                  {
                    "id"  => "d1",
                    "properties"  => {
                      "privateIPAddress"  => "e1",
                      "privateIPAllocationMethod"  => "f1"
                    }
                  }
                ],
                "dnsSettings"  => {
                   "dnsServers"  => [
                      "g",
                      "h"
                   ]
                }
              }
            },
            {
              "name"  => "the-name-witout-keyword",
              "id"  => "a",
              "location"  => "b",
              "tags"  => {},
              "properties"  => {
                "provisioningState"  => "c",
                "ipConfigurations"  => [
                  {
                    "id"  => "d2",
                    "properties"  => {
                      "privateIPAddress"  => "e2",
                      "privateIPAllocationMethod"  => "f2"
                    }
                  }
                ],
                "dnsSettings"  => {
                   "dnsServers"  => [
                      "g",
                      "h"
                   ]
                }
              }
            }
          ]
        }.to_json
      }
      let(:network_interface_0) {
        {
          :id=>"a",
          :name=>"#{instance_id}-0",
          :location=>"b",
          :tags=>{},
          :provisioning_state=>"c",
          :dns_settings=>["g", "h"],
          :ip_configuration_id=>"d0",
          :private_ip=>"e0",
          :private_ip_allocation_method=>"f0"
        }
      }
      let(:network_interface_1) {
        {
          :id=>"a",
          :name=>"#{instance_id}-1",
          :location=>"b",
          :tags=>{},
          :provisioning_state=>"c",
          :dns_settings=>["g", "h"],
          :ip_configuration_id=>"d1",
          :private_ip=>"e1",
          :private_ip_allocation_method=>"f1"
        }
      }

      it "should return network interfaces" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, network_interfaces_url).to_return(
          :status => 200,
          :body => result,
          :headers => {
          })

        expect(
          azure_client2.list_network_interfaces_by_keyword(resource_group, instance_id)
        ).to eq([network_interface_0, network_interface_1])
      end
    end
  end
end
