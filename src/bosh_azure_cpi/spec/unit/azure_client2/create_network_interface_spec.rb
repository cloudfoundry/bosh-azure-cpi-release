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
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:resource_group) { "fake-resource-group-name" }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_network_interface" do
    let(:network_interface_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/#{nic_name}?api-version=#{api_version_network}" }

    let(:nic_name) { "fake-nic-name" }
    let(:nsg_id) { "fake-nsg-id" }
    let(:subnet) { {:id => "fake-subnet-id"} }
    let(:tags) { {"foo" => "bar"} }

    context "when token is valid, create operation is accepted and completed" do
      context "with private ip, public ip and dns servers" do
        let(:nic_params) {
          {
            :name => nic_name,
            :location => "fake-location",
            :ipconfig_name => "fake-ipconfig-name",
            :private_ip => "10.0.0.100",
            :dns_servers => ["168.63.129.16"],
            :public_ip => {:id => "fake-public-id"},
            :network_security_group => {:id => nsg_id},
            :application_security_groups => []
          }
        }
        let(:load_balancer) { nil }
        let(:request_body) {
          {
            :name     => nic_params[:name],
            :location => nic_params[:location],
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :networkSecurityGroup => {
                :id => nic_params[:network_security_group][:id]
              },
              :ipConfigurations => [{
                :name        => nic_params[:ipconfig_name],
                :properties  => {
                  :privateIPAddress          => nic_params[:private_ip],
                  :privateIPAllocationMethod => "Static",
                  :publicIPAddress           => { :id => nic_params[:public_ip][:id] },
                  :subnet => {
                    :id => subnet[:id]
                  },
                  :applicationSecurityGroups => []
                }
              }],
              :dnsSettings => {
                :dnsServers => ["168.63.129.16"]
              }
            }
          }
        }

        it "should create a network interface without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, network_interface_uri).to_return(
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
            azure_client2.create_network_interface(resource_group, nic_params, subnet, tags, nil)
          }.not_to raise_error
        end
      end

      context "without private ip, public ip and dns servers" do
        let(:nic_params) {
          {
            :name => nic_name,
            :location => "fake-location",
            :ipconfig_name => "fake-ipconfig-name",
            :network_security_group => {:id => nsg_id},
            :application_security_groups => []
          }
        }
        let(:load_balancer) { nil }
        let(:request_body) {
          {
            :name     => nic_params[:name],
            :location => nic_params[:location],
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :networkSecurityGroup => {
                :id => nic_params[:network_security_group][:id]
              },
              :ipConfigurations => [{
                :name        => nic_params[:ipconfig_name],
                :properties  => {
                  :privateIPAddress          => nil,
                  :privateIPAllocationMethod => "Dynamic",
                  :publicIPAddress           => nil,
                  :subnet => {
                    :id => subnet[:id]
                  },
                  :applicationSecurityGroups => []
                }
              }],
              :dnsSettings => {
                :dnsServers => []
              }
            }
          }
        }

        it "should create a network interface without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, network_interface_uri).to_return(
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
            azure_client2.create_network_interface(resource_group, nic_params, subnet, tags, nil)
          }.not_to raise_error
        end
      end

      context "with load balancer" do
        let(:nic_params) {
          {
            :name => nic_name,
            :location => "fake-location",
            :ipconfig_name => "fake-ipconfig-name",
            :private_ip => "10.0.0.100",
            :dns_servers => ["168.63.129.16"],
            :public_ip => {:id => "fake-public-id"},
            :network_security_group => {:id => nsg_id},
            :application_security_groups => []
          }
        }
        let(:load_balancer) {
          {
            :backend_address_pools => [
              {
                :id => "fake-id"
              }
            ],
            :frontend_ip_configurations => [{
              :inbound_nat_rules => [{}]
            }]
          }
        }
        let(:request_body) {
          {
            :name     => nic_params[:name],
            :location => nic_params[:location],
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :networkSecurityGroup => {
                :id => nic_params[:network_security_group][:id]
              },
              :ipConfigurations => [{
                :name        => nic_params[:ipconfig_name],
                :properties  => {
                  :privateIPAddress          => nic_params[:private_ip],
                  :privateIPAllocationMethod => "Static",
                  :publicIPAddress           => { :id => nic_params[:public_ip][:id] },
                  :subnet => {
                    :id => subnet[:id]
                  },
                  :applicationSecurityGroups => []
                }
              }],
              :dnsSettings => {
                :dnsServers => ["168.63.129.16"]
              }
            }
          }
        }

        it "should create a network interface without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, network_interface_uri).to_return(
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
            azure_client2.create_network_interface(resource_group, nic_params, subnet, tags, load_balancer)
          }.not_to raise_error
        end
      end

      context "with application security groups" do
        let(:nic_params) {
          {
            :name => nic_name,
            :location => "fake-location",
            :ipconfig_name => "fake-ipconfig-name",
            :private_ip => "10.0.0.100",
            :dns_servers => ["168.63.129.16"],
            :public_ip => {:id => "fake-public-id"},
            :network_security_group => {:id => nsg_id},
            :application_security_groups => [{:id => "fake-asg-id-1"}, {:id => "fake-asg-id-2"}]
          }
        }
        let(:load_balancer) {
          {
            :backend_address_pools => [
              {
                :id => "fake-id"
              }
            ],
            :frontend_ip_configurations => [{
              :inbound_nat_rules => [{}]
            }]
          }
        }
        let(:request_body) {
          {
            :name     => nic_params[:name],
            :location => nic_params[:location],
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :networkSecurityGroup => {
                :id => nic_params[:network_security_group][:id]
              },
              :ipConfigurations => [{
                :name        => nic_params[:ipconfig_name],
                :properties  => {
                  :privateIPAddress          => nic_params[:private_ip],
                  :privateIPAllocationMethod => "Static",
                  :publicIPAddress           => { :id => nic_params[:public_ip][:id] },
                  :subnet => {
                    :id => subnet[:id]
                  },
                  :applicationSecurityGroups => [
                    {
                      :id => "fake-asg-id-1"
                    },
                    {
                      :id => "fake-asg-id-2"
                    }
                  ]
                }
              }],
              :dnsSettings => {
                :dnsServers => ["168.63.129.16"]
              }
            }
          }
        }

        it "should create a network interface without error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token"=>valid_access_token,
              "expires_on"=>expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, network_interface_uri).to_return(
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
            azure_client2.create_network_interface(resource_group, nic_params, subnet, tags, load_balancer)
          }.not_to raise_error
        end
      end
    end
  end
end
