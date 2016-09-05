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

  let(:vm_name) { "fake-vm-name" }
  let(:valid_access_token) { "valid-access-token" }
  let(:invalid_access_token) { "invalid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_virtual_machine" do
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version}&validating=true" }

    let(:vm_params) do
      {
        :name           => vm_name,
        :location       => "b",
        :vm_size        => "c",
        :username       => "d",
        :ssh_cert_data  => "e",
        :custom_data    => "f",
        :image_uri      => "g",
        :os_disk        => {
          :disk_name     => "h",
          :disk_uri      => "i",
          :disk_caching  => "j",
          :disk_size     => "k",
        },
        :ephemeral_disk => {
          :disk_name     => "l",
          :disk_uri      => "m",
          :disk_caching  => "n",
          :disk_size     => "o",
        }
      }
    end
    let(:network_interfaces) {[
      {:id => "a"},
      {:id => "a"}
    ]}

    context "when token is valid, create operation is accepted and completed" do
      context "When the ephemeral disk is not nil" do
        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
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
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "When the ephemeral disk is nil" do
        let(:vm_params) do
          {
            :name           => vm_name,
            :location       => "b",
            :vm_size        => "c",
            :username       => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j",
              :disk_size     => "k",
            }
          }
        end

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
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
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "When the os_disk.size is nil" do
        let(:vm_params) do
          {
            :name           => vm_name,
            :location       => "b",
            :vm_size        => "c",
            :username       => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j"
            }
          }
        end

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
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
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
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
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /get_token - http code: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end
    end

    context "when token expired" do
      context "when authentication retry succeeds" do
        before do
          stub_request(:post, token_uri).to_return({
              :status => 200,
              :body => {
                "access_token"=>valid_access_token,
                "expires_on"=>expires_on
              }.to_json,
              :headers => {}
            })
          stub_request(:put, vm_uri).to_return({
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
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "when authentication retry fails" do
        before do
          stub_request(:post, token_uri).to_return({
              :status => 200,
              :body => {
                "access_token"=>valid_access_token,
                "expires_on"=>expires_on
              }.to_json,
              :headers => {}
            }, {
              :status => 401,
              :body => '',
              :headers => {}
            })
          stub_request(:put, vm_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            })
        end

        it "should raise an error if authentication retry fails" do
          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
        end
      end
    end

    context "when another process is operating the same VM" do
      it "should raise AzureConflictError" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 409,
          :body => 'Another process is operating the same VM',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error Bosh::AzureCloud::AzureConflictError
      end
    end

    context "when network interface count exceeds the max allowed NIC number" do
      it "should raise AzureError" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 400,
          :body => 'The number of network interfaces for virtual machine xxx exceeds the maximum allowed for the virtual machine size Standard_D1.',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /The number of network interfaces for virtual machine xxx exceeds the maximum/
      end
    end

    context "when token is valid, create operation is accepted and not completed" do
      it "should raise an error if check completion operation is not accepeted" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /check_completion - http code: 404/
      end

      it "should raise an error if create operation failed" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Cancelled"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /status: Cancelled/
      end
    end
  end
end
