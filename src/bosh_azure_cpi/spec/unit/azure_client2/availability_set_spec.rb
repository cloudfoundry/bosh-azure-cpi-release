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

  let(:avset_name) { "fake-avset-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_availability_set" do
    let(:avset_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/#{avset_name}?api-version=#{api_version_compute}" }

    let(:avset_params) {
      {
        :name                         => avset_name,
        :location                     => "fake-location",
        :tags                         => { "foo" => "bar"},
        :platform_update_domain_count => 5,
        :platform_fault_domain_count  => 2
      }
    }

    let(:request_body) {
      {
        :name => avset_name,
        :location => "fake-location",
        :type => "Microsoft.Compute/availabilitySets",
        :tags     => {
          :foo => "bar"
        },
        :sku => {
          :name => "Classic"
        },
        :properties => {
          :platformUpdateDomainCount => 5,
          :platformFaultDomainCount  => 2
        }
      }
    }
    
    context "When managed is null" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client2.create_availability_set(avset_params)
        }.not_to raise_error
      end
    end

    context "When managed is false" do
      before do
        avset_params[:managed] = false
      end

      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client2.create_availability_set(avset_params)
        }.not_to raise_error
      end
    end

    context "When managed is true" do
      before do
        avset_params[:managed] = true
        request_body[:sku][:name] = "Aligned"
      end

      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client2.create_availability_set(avset_params)
        }.not_to raise_error
      end
    end
  end

  describe "#get_availability_set_by_name" do
    let(:avset_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/#{avset_name}?api-version=#{api_version_compute}" }

    let(:response_body) {
      {
        :id => "a",
        :name => avset_name,
        :location => "c",
        :tags     => {
          :foo => "bar"
        },
        :sku => {
          :name => "Aligned"
        },
        :properties => {
          :provisioningState => "d",
          :platformUpdateDomainCount => 5,
          :platformFaultDomainCount => 2,
        }
      }
    }
    let(:avset) {
      {
        :id => "a",
        :name => avset_name,
        :location => "c",
        :tags     => {
          "foo" => "bar"
        },
        :provisioning_state => "d",
        :platform_update_domain_count => 5,
        :platform_fault_domain_count => 2,
        :managed => true,
        :virtual_machines => []
      }
    }

    context "when there are no machines in the availibility set" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, avset_uri).to_return(
          :status => 200,
          :body => response_body.to_json,
          :headers => {})

        expect(
          azure_client2.get_availability_set_by_name(avset_name)
        ).to eq(avset)
      end
    end

    context "when there are machines in the availibility set" do
      before do
      response_body[:properties][:virtualMachines] = [
        {
          :id => "vm-id-1"
        },
        {
          :id => "vm-id-2"
        }
      ]
      avset[:virtual_machines] = response_body[:properties][:virtualMachines]
      end

      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, avset_uri).to_return(
          :status => 200,
          :body => response_body.to_json,
          :headers => {})

        expect(
          azure_client2.get_availability_set_by_name(avset_name)
        ).to eq(avset)
      end
    end
  end
end
