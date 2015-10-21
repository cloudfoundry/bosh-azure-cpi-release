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

  let(:token_uri) { "https://login.windows.net/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { "fake-vm-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:invalid_access_token) { "invalid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#delete_virtual_machine" do
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version}" }

    context "when token is valid" do
      before do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
      end

      it "should raise an error if delete opration returns 404" do
        stub_request(:delete, vm_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {
          })

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error /http_delete - error: 404/
      end

      it "should raise no error if delete opration returns 200" do
        stub_request(:delete, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
          })

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.not_to raise_error
      end

      it "should raise no error if delete opration returns 204" do
        stub_request(:delete, vm_uri).to_return(
          :status => 204,
          :body => '',
          :headers => {
          })

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.not_to raise_error
      end

      context "when delete operation needs to check (returns 202)" do
        it "should raise no error if operation status is Succeeded" do
          stub_request(:delete, vm_uri).to_return(
            :status => 202,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.not_to raise_error
        end

        # TODO
        it "should raise no error if operation status is InProgress at first and Succeeded finally" do
        end

        it "should raise an error if check completion operation is not accepeted" do
          stub_request(:delete, vm_uri).to_return(
            :status => 202,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 404,
            :body => '',
            :headers => {})

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.to raise_error /check_completion - http error: 404/
        end

        it "should raise an error if create peration failed" do
          stub_request(:delete, vm_uri).to_return(
            :status => 202,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Failed"}',
            :headers => {})

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.to raise_error /status: Failed/
        end
      end
    end

    context "when token is invalid" do
      it "should raise an error if token is not gotten" do
        stub_request(:post, token_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error /get_token - http error: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error /get_token - Azure authentication failed: invalid tenant id, client id or client secret./
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:delete, vm_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end

      # TODO
      it "should not raise an error if authentication retry succeeds" do
      end
    end
  end
end
