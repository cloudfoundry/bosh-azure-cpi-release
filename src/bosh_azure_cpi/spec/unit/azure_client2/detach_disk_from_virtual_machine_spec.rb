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

  let(:vm_name) { "fake-vm-name" }
  let(:tags) { {} }

  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#detach_disk_to_virtual_machine" do
    disk_name = "fake-disk-name"
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }
    let(:response_body) {
      {
        "id" => "fake-id",
        "name" => "fake-name",
        "location" => "fake-location",
        "tags" => "fake-tags",
        "properties" => {
          "provisioningState" => "fake-state",
          "storageProfile" => {
            "dataDisks" => [
              {
                "name" => disk_name,
                "lun" => 1
              },
              {
                "name" => "wrong name",
                "lun" => 0
              }
            ]
          }
        }
      }.to_json
    }

    context "when token is valid, create operation is accepted and completed" do
      let(:request_body) {
        {
          "id" => "fake-id",
          "name" => "fake-name",
          "location" => "fake-location",
          "tags" => "fake-tags",
          "properties" => {
            "provisioningState" => "fake-state",
            "storageProfile" => {
              "dataDisks" => [
                {
                  "name" => "wrong name",
                  "lun" => 0
                }
              ]
            }
          }
        }
      }

      context "when VM's information does not contain 'resources'" do
        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:get, vm_uri).to_return(
            :status => 200,
            :body => response_body,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client2.detach_disk_from_virtual_machine(vm_name, disk_name)
          }.not_to raise_error
        end
      end

      context "when VM's information contains 'resources'" do
        let(:response_body_with_resources) {
          {
            "id" => "fake-id",
            "name" => "fake-name",
            "location" => "fake-location",
            "tags" => "fake-tags",
            "properties" => {
              "provisioningState" => "fake-state",
              "storageProfile" => {
                "dataDisks" => [
                  {
                    "name" => disk_name,
                    "lun" => 1
                  },
                  {
                    "name" => "wrong name",
                    "lun" => 0
                  }
                ]
              }
            },
            "resources" => [
              {
                "properties": {},
                "id": "fake-id",
                "name": "fake-name",
                "type": "fake-type",
                "location": "fake-location"
              }
            ]
          }.to_json
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:get, vm_uri).to_return(
            :status => 200,
            :body => response_body_with_resources,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client2.detach_disk_from_virtual_machine(vm_name, disk_name)
          }.not_to raise_error
        end
      end
    end

    context "when the virtual machine is not found" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        stub_request(:put, vm_uri).to_return(
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
          azure_client2.detach_disk_from_virtual_machine(vm_name, disk_name)
        }.to raise_error /detach_disk_from_virtual_machine - cannot find the virtual machine by name/
      end
    end

    context "when the disk is not found" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => response_body,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        disk_name = "another-disk-name"
        expect {
          azure_client2.detach_disk_from_virtual_machine(vm_name, disk_name)
        }.to raise_error /The disk #{disk_name} is not attached to the virtual machine #{vm_name}/
      end
    end
  end
end
