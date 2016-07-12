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
  let(:api_version) { '2015-05-01-preview' }
  let(:resource_group) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { "fake-vm-name" }
  let(:tags) { {} }

  let(:valid_access_token) { "valid-access-token" }
  let(:invalid_access_token) { "invalid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#attach_disk_to_virtual_machine" do
    let(:disk_name) { "fake-disk-name" }
    let(:disk_uri) { "fake-disk-uri" }
    let(:caching) { "ReadWrite" }
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version}" }
    let(:disk) {
      {
        :name         => disk_name,
        :lun          => 2,
        :createOption => 'Attach',
        :caching      => 'ReadWrite',
        :vhd          => { :uri => disk_uri }
      }
    }

    context "when token is valid, create operation is accepted and completed" do
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
                { "lun" => 0 },
                { "lun" => 1 }
              ]
            },
            "hardwareProfile" => {
              "vmSize" => "Standard_A5"
            }
          }
        }.to_json
      }

      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
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

        expect(
          azure_client2.attach_disk_to_virtual_machine(vm_name, disk_name, disk_uri, caching)
        ).to eq(disk)
      end
    end

    context "when the virtual machine is not found" do
      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})

        expect {
          azure_client2.attach_disk_to_virtual_machine(vm_name, disk_name, disk_uri, caching)
        }.to raise_error /attach_disk_to_virtual_machine - cannot find the virtual machine by name/
      end
    end

    context "when no avaiable lun can be found" do
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
                { "lun" => 0 },
                { "lun" => 1 }
              ]
            },
            "hardwareProfile" => {
              "vmSize" => "Standard_A1"
            }
          }
        }.to_json
      }

      it "should raise an error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => response_body,
          :headers => {})

        expect {
          azure_client2.attach_disk_to_virtual_machine(vm_name, disk_name, disk_uri, caching)
        }.to raise_error /attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine/
      end
    end
  end
end
