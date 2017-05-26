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

  describe "#attach_disk_to_virtual_machine" do
    let(:disk_name) { "fake-disk-name" }
    let(:caching) { "ReadWrite" }
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }

    context "when attaching a managed disk" do
      let(:disk_id) { "fake-disk-id" }
      let(:disk_params) {
        {
          :disk_name => disk_name,
          :caching   => caching,
          :disk_id   => disk_id,
          :managed   => true
         }
      }
      let(:disk) {
        {
          :name          => disk_name,
          :lun           => 2,
          :create_option => 'Attach',
          :caching       => caching,
          :managed_disk  => { :id => disk_id }
         }
      }
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
                { "lun" => 0 },
                { "lun" => 1 },
                {
                  "name" => disk_name,
                  "lun"  => 2,
                  "createOption" => "Attach",
                  "caching"      => caching,
                  "managedDisk"  => { "id" => disk_id }
                }
              ]
            },
            "hardwareProfile" => {
              "vmSize" => "Standard_A5"
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

        expect(
          azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
        ).to eq(disk)
      end
    end

    context "when attaching an unmanaged disk" do
      let(:disk_uri) { "fake-disk-uri" }
      let(:disk_size) { 42 }
      let(:disk_params) {
        {
          :disk_name => disk_name,
          :caching   => caching,
          :disk_uri  => disk_uri,
          :disk_size => disk_size,
          :managed   => false
         }
      }
      let(:disk) {
        {
          :name          => disk_name,
          :lun           => 2,
          :create_option => 'Attach',
          :caching       => caching,
          :disk_size_gb  => disk_size,
          :vhd           => { :uri => disk_uri }
        }
      }
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
                { "lun" => 0 },
                { "lun" => 1 },
                {
                  "name" => disk_name,
                  "lun"  => 2,
                  "createOption" => "Attach",
                  "caching"      => caching,
                  "diskSizeGb"   => disk_size,
                  "vhd"          => { "uri" => disk_uri }
                }
              ]
            },
            "hardwareProfile" => {
              "vmSize" => "Standard_A5"
            }
          }
        }
      }

      context "when VM's information does not contain 'resources'" do
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

          expect(
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
          ).to eq(disk)
        end
      end

      context "when VM's information contains 'resources'" do
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

          expect(
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
          ).to eq(disk)
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

          expect {
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
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
                "vmSize" => "Standard_A1" # Standard_A1 only has 2 available luns
              }
            }
          }.to_json
        }

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

          expect {
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
          }.to raise_error /attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine/
        end
      end

      context "if put operation returns retryable error code (returns 429)" do
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

        it "should raise error if it always returns 429" do
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
            {
              :status => 429,
              :body => '',
              :headers => {
              }
            }
          )

          expect {
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
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
          stub_request(:get, vm_uri).to_return(
            :status => 200,
            :body => response_body,
            :headers => {})
          stub_request(:put, vm_uri).to_return(
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
                "azure-asyncoperation" => operation_status_link
              }
            }
          )
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.attach_disk_to_virtual_machine(vm_name, disk_params)
          }.not_to raise_error
        end
      end
    end
  end
end
