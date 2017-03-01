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
  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#delete_virtual_machine" do
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }

    context "when token is valid" do
      before do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
      end

      it "should raise AzureNotFoundError if delete opration returns 404" do
        stub_request(:delete, vm_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {
          })

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error Bosh::AzureCloud::AzureNotFoundError
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

      # Fit for all errors with status code in AZURE_RETRY_ERROR_CODES ([408, 429, 500, 502, 503, 504])
      context "when delete operation returns retryable error code (returns 429)" do
        # This case will take long time to complete because it retry 10 times.
        it "should raise error if delete opration always returns 429" do
          stub_request(:delete, vm_uri).to_return(
            {
              :status => 429,
              :body => '',
              :headers => {
              }
            })

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.to raise_error Bosh::AzureCloud::AzureInternalError
        end

        it "should not raise error if delete opration returns 429 at the first time but returns 200 at the second time" do
          stub_request(:delete, vm_uri).to_return(
            {
              :status => 429,
              :body => '',
              :headers => {
              }
            },
            {
              :status => 200,
              :body => '',
              :headers => {
              }
            }
          )

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.not_to raise_error
        end
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

        it "should not loop forever or raise an error if operation status is InProgress at first and Succeeded finally" do
          stub_request(:delete, vm_uri).to_return(
            :status => 202,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            {
              :status => 200,
              :body => '{"status":"InProgress"}',
              :headers => {}
            },
            {
              :status => 200,
              :body => '{"status":"Succeeded"}',
              :headers => {}
            }
          )

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.not_to raise_error
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
          }.to raise_error /check_completion - http code: 404/
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
            :body => '{"status":"Cancelled"}',
            :headers => {})

          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.to raise_error /status: Cancelled/
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
        }.to raise_error /get_token - http code: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.delete_virtual_machine(vm_name)
        }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
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
    end

    context "when token expired" do
      context "when authentication retry succeeds" do
        before do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:delete, vm_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            }, {
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              }
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})
        end

        it "should not raise an error" do
          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.not_to raise_error
        end
      end

      context "when authentication retry fails" do
        before do
          stub_request(:post, token_uri).to_return({
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {}
            }, {
              :status => 401,
              :body => ''
            })
          stub_request(:delete, vm_uri).to_return(
              :status => 401,
              :body => 'The token expired'
            )
        end

        it "should raise an error" do
          expect {
            azure_client2.delete_virtual_machine(vm_name)
          }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
        end
      end
    end
  end
end
