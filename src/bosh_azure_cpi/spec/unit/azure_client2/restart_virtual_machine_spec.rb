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

  describe "#restart_virtual_machine" do
    let(:vm_restart_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}/restart?api-version=#{api_version_compute}" }

    context "when token is valid, restart operation is accepted and completed" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.not_to raise_error
      end

      it "should not loop forever or raise an error if restart operation is InProgress at first and Succeeded finally" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
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
          azure_client2.restart_virtual_machine(vm_name)
        }.not_to raise_error
      end
    end

    context "when token is invalid" do
      it "should raise an error if token is not gotten" do
        stub_request(:post, token_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /get_token - http code: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
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
        stub_request(:post, vm_restart_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end
    end

    context "when token is valid but the VM cannot be found" do
      it "should raise AzureNotFoundError" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error Bosh::AzureCloud::AzureNotFoundError
      end
    end

    context "when token is valid, restart operation is accepted and not completed" do
      it "should raise an error if check completion operation is not acceptted" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /check_completion - http code: 404/
      end

      it "should raise an error if restart operation failed" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          :status => 202,
          :body => '{}',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Cancelled"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error /status: Cancelled/
      end

      # TODO
      it "should cause an endless loop if restart operation is always InProgress" do
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
          stub_request(:post, vm_restart_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            }, {
              :status => 202,
              :body => '{}',
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
            azure_client2.restart_virtual_machine(vm_name)
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
              :body => '',
              :headers => {}
            })
          stub_request(:post, vm_restart_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            })
        end

        it "should raise an error" do
          expect {
            azure_client2.restart_virtual_machine(vm_name)
          }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
        end
      end
    end

    context "if post operation returns retryable error code (returns 429)" do
      it "should raise error if it always returns 429" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          {
            :status => 429,
            :body => '{}',
            :headers => {}
          }
        )

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.to raise_error Bosh::AzureCloud::AzureInternalError
      end

      it "should not raise error if it returns 429 at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:post, vm_restart_uri).to_return(
          {
            :status => 429,
            :body => '{}',
            :headers => {}
          },
          {
            :status => 202,
            :body => '{}',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            }
          }
        )
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.restart_virtual_machine(vm_name)
        }.not_to raise_error
      end
    end
  end
end
