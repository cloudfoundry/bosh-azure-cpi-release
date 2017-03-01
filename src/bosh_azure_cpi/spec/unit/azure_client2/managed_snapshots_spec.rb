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
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:snapshot_name) { "fake-snapshot-name" }
  let(:disk_name) { "fake-disk-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_managed_snapshot" do
    let(:snapshot_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/#{snapshot_name}?api-version=#{api_version_compute}" }
    let(:disk_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:snapshot_params) do
      {
        :name           => snapshot_name,
        :location       => "a",
        :tags           => {
          :snapshot => snapshot_name
        },
        :disk_name      => disk_name
      }
    end

    let(:disk_response_body) {
      {
        :id => "a",
        :name => "b",
        :location => "c",
        :tags     => {
          :disk => disk_name
        },
        :properties => {
          :provisioningState => "d",
          :diskSizeGB => "e",
          :accountType => "f"
        }
      }
    }

    let(:request_body) {
      {
        :location => "c",
        :tags     => {
          "snapshot" => snapshot_name
        },
        :properties => {
          :creationData => {
            :createOption => "Copy",
            :sourceUri => "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}"
          }
        }
      }
    }

    it "should raise no error" do
      stub_request(:post, token_uri).to_return(
        :status => 200,
        :body => {
          "access_token" => valid_access_token,
          "expires_on" => expires_on
        }.to_json,
        :headers => {})
      stub_request(:get, disk_uri).to_return(
        :status => 200,
        :body => disk_response_body.to_json,
        :headers => {})
      stub_request(:put, snapshot_uri).with(body: request_body).to_return(
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
        azure_client2.create_managed_snapshot(snapshot_params)
      }.not_to raise_error
    end
  end

end
