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

  let(:disk_name) { "fake-disk-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_empty_managed_disk" do
    let(:disk_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:disk_params) do
      {
        :name           => disk_name,
        :location       => "b",
        :tags           => { "foo" => "bar"},
        :disk_size      => "c",
        :account_type   => "d"
      }
    end

    let(:request_body) {
      {
        :location => "b",
        :tags     => {
          :foo => "bar"
        },
        :properties => {
          :creationData => {
            :createOption => "Empty"
          },
          :accountType => "d",
          :diskSizeGB => "c"
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
      stub_request(:put, disk_uri).with(body: request_body).to_return(
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
        azure_client2.create_empty_managed_disk(disk_params)
      }.not_to raise_error
    end
  end

  describe "#create_managed_disk_from_blob" do
    let(:disk_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:disk_params) do
      {
        :name           => disk_name,
        :location       => "b",
        :tags           => { "foo" => "bar"},
        :source_uri     => "c",
        :account_type   => "d"
      }
    end

    let(:request_body) {
      {
        :location => "b",
        :tags     => {
          :foo => "bar"
        },
        :properties => {
          :creationData => {
            :createOption => "Import",
            :sourceUri => "c"
          },
          :accountType => "d"
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
      stub_request(:put, disk_uri).with(body: request_body).to_return(
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
        azure_client2.create_managed_disk_from_blob(disk_params)
      }.not_to raise_error
    end
  end

  describe "#get_managed_disk_by_name" do
    let(:disk_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:response_body) {
      {
        :id => "a",
        :name => "b",
        :location => "c",
        :tags     => {
          :foo => "bar"
        },
        :properties => {
          :provisioningState => "d",
          :diskSizeGB => "e",
          :accountType => "f"
        }
      }
    }
    let(:disk) {
      {
        :id => "a",
        :name => "b",
        :location => "c",
        :tags     => {
          "foo" => "bar"
        },
        :provisioning_state => "d",
        :disk_size => "e",
        :account_type => "f"
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
        :body => response_body.to_json,
        :headers => {})

      expect(
        azure_client2.get_managed_disk_by_name(disk_name)
      ).to eq(disk)
    end
  end

  describe "#get_tags_of_managed_disk" do
    let(:disk_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    context "the managed disk exists" do
      let(:response_body) {
        {
          :id => "a",
          :name => "b",
          :location => "c",
          :tags     => {
            :foo => "bar"
          },
          :properties => {
            :provisioningState => "d",
            :diskSizeGB => "e",
            :accountType => "f"
          }
        }
      }
      let(:disk) {
        {
          :id => "a",
          :name => "b",
          :location => "c",
          :tags     => {
            "foo" => "bar"
          },
          :provisioning_state => "d",
          :disk_size => "e",
          :account_type => "f"
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
          :body => response_body.to_json,
          :headers => {})

        expect(
          azure_client2.get_tags_of_managed_disk(disk_name)
        ).to eq({"foo" => "bar"})
      end
    end

    context "the managed disk does not exist" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, disk_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})

        expect {
          azure_client2.get_tags_of_managed_disk(disk_name)
        }.to raise_error(/get_tags_of_managed_disk - cannot find the managed disk by name `#{disk_name}'/)
      end
    end
  end
end
