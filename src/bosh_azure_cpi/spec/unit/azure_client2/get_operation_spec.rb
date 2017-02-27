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
  let(:resource_group_name) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  # Public IP
  let(:public_ip_name) { "fake-name" }
  let(:public_ip_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}" }
  let(:public_ip_uri) { "https://management.azure.com/#{public_ip_id}?api-version=#{api_version}" }
  let(:public_ip_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "resourceGuid" => "fake-guid",
        "provisioningState" => "fake-state",
        "ipAddress" => "123.123.123.123",
        "publicIPAllocationMethod" => "Dynamic",
        "publicIPAddressVersion" => "fake-version",
        "idleTimeoutInMinutes" => 4,
        "ipConfigurations" => {"id"=>"fake-id"},
        "dnsSettings" => {
          "domainNameLabel"=>"foo",
          "fqdn"=>"bar",
          "reverseFqdn"=>"ooo"
        }
      }
    }
  }
  let(:fake_public_ip) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :tags => "fake-tags",
      :resource_guid => "fake-guid",
      :provisioning_state => "fake-state",
      :ip_address => "123.123.123.123",
      :public_ip_allocation_method => "Dynamic",
      :public_ip_address_version => "fake-version",
      :idle_timeout_in_minutes => 4,
      :ip_configuration_id => "fake-id",
      :domain_name_label => "foo",
      :fqdn => "bar",
      :reverse_fqdn => "ooo"
    }
  }

  # Load Balancer
  let(:load_balancer_name) { "fake-name" }
  let(:load_balancer_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/#{load_balancer_name}" }
  let(:load_balancer_uri) { "https://management.azure.com/#{load_balancer_id}?api-version=#{api_version}" }
  let(:load_balancer_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "provisioningState" => "fake-state",
        "frontendIPConfigurations" => [{
          "name" => "fake-name",
          "id" => "fake-id",
          "properties" => {
            "provisioningState" => "fake-state",
            "privateIPAllocationMethod" => "bar",
            "publicIPAddress" => {
              "id" => public_ip_id
            },
            "inboundNatRules" => []
          }
        }],
        "backendAddressPools" => [{
          "name" => "fake-name",
          "id" => "fake-id",
          "properties" => {
            "provisioningState" => "fake-state",
            "backendIPConfigurations" => []
          }
        }]
      }
    }.to_json
  }
  let(:fake_load_balancer) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :tags => "fake-tags",
      :provisioning_state => "fake-state",
      :frontend_ip_configurations => [
        {
          :id => "fake-id",
          :name => "fake-name",
          :provisioning_state => "fake-state",
          :private_ip_allocation_method => "bar",
          :public_ip => fake_public_ip,
          :inbound_nat_rules => []
        }
      ],
      :backend_address_pools => [
        {
          :name => "fake-name",
          :id => "fake-id",
          :provisioning_state => "fake-state",
          :backend_ip_configurations => []
        }
      ]
    }
  }
    
  # Network Interface
  let(:nic_name) { "fake-name" }
  let(:nic_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/networkInterfaces/#{nic_name}" }
  let(:nic_uri) { "https://management.azure.com/#{nic_id}?api-version=#{api_version}" }

  let(:nic_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "provisioningState" => "fake-state",
        "dnsSettings" => {
          "dnsServers" => ["168.63.129.16"]
        },
        "ipConfigurations" => [
          {
            "id" => "fake-id",
            "properties" => {
              "privateIPAddress" => "10.0.0.100",
              "privateIPAllocationMethod" => "Dynamic",
              "publicIPAddress" => {
                "id" => public_ip_id
              },
              "loadBalancerBackendAddressPools" => [{
                "id" => load_balancer_id
              }]
            }
          }
        ]
      }
    }.to_json
  }
  let(:fake_nic) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :tags => "fake-tags",
      :provisioning_state => "fake-state",
      :dns_settings => ["168.63.129.16"],
      :ip_configuration_id => "fake-id",
      :private_ip => "10.0.0.100",
      :private_ip_allocation_method => "Dynamic",
      :public_ip => fake_public_ip,
      :load_balancer => fake_load_balancer
    }
  }

  # Subnet
  let(:vnet_name) { "fake-name" }
  let(:subnet_name) { "bar" }
  let(:network_subnet_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/virtualNetworks/#{vnet_name}/subnets/#{subnet_name}?api-version=#{api_version}" }
  let(:network_subnet_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "properties" => {
        "provisioningState" => "fake-state",
        "addressPrefix" => "10.0.0.0",
      }
    }.to_json
  }
  let(:fake_network_subnet) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :provisioning_state => "fake-state",
      :address_prefix => "10.0.0.0"
    }
  }

  # Network Security Group
  let(:nsg_name) { "fake-name" }
  let(:nsg_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/networkSecurityGroups/#{nsg_name}" }
  let(:nsg_uri) { "https://management.azure.com/#{nsg_id}?api-version=#{api_version}" }

  let(:nsg_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "provisioningState" => "fake-state",
        "securityRules" => [
          {
            "name" => "fake-rule-name",
            "id" => "fake-rule-id",
            "etag" => "00000000-0000-0000-0000-000000000000",
            "properties" => {
               "provisioningState" => "Succeeded",
               "description" => "description-of-this-rule",
               "protocol" =>  "*",
               "sourcePortRange" => "source-port-range",
               "destinationPortRange" => "destination-port-range",
               "sourceAddressPrefix" => "*",
               "destinationAddressPrefix" => "*",
               "access" => "Allow",
               "priority" =>  200,
               "direction" => "Inbound"
            }
          }
        ],
        "defaultSecurityRules" => [
          {
            "name" => "AllowVnetInBound",
            "id" => "fake-default-rule-id",
            "etag" => "00000000-0000-0000-0000-000000000000",
            "properties" => {
               "provisioningState" => "Succeeded",
               "description" => "description-of-this-rule",
               "protocol" =>  "*",
               "sourcePortRange" => "*",
               "destinationPortRange" => "*",
               "sourceAddressPrefix" => "VirtualNetwork",
               "destinationAddressPrefix" => "VirtualNetwork",
               "access" => "Allow",
               "priority" => 65000,
               "direction" => "Inbound"
            }
          }
        ],
        "networkInterfaces" => [],
        "subnets" => []
      }
    }.to_json
  }
  let(:fake_nsg) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :tags => "fake-tags",
      :provisioning_state => "fake-state"
    }
  }

  before do
    stub_request(:post, token_uri).to_return(
      :status => 200,
      :body => {
        "access_token" => valid_access_token,
        "expires_on" => expires_on
      }.to_json,
      :headers => {})
  end

  describe "#get_public_ip_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_public_ip_by_name(public_ip_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.get_public_ip_by_name(public_ip_name)
        ).to eq(fake_public_ip)
      end
    end
  end

  describe "#list_public_ips" do
    let(:list_public_ips_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/publicIPAddresses?api-version=#{api_version}" }
    let(:list_public_ips_response_body) {
      {
        "value" => [public_ip_response_body]
      }
    }
    let(:fake_public_ip_list) {
      [fake_public_ip]
    }
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, list_public_ips_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.list_public_ips(resource_group_name)
        ).to eq([])
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, list_public_ips_uri).to_return(
          :status => 200,
          :body => list_public_ips_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.list_public_ips(resource_group_name)
        ).to eq(fake_public_ip_list)
      end
    end
  end

  describe "#get_load_balancer_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, load_balancer_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_load_balancer_by_name(load_balancer_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, load_balancer_uri).to_return(
          :status => 200,
          :body => load_balancer_response_body,
          :headers => {})
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.get_load_balancer_by_name(load_balancer_name)
        ).to eq(fake_load_balancer)
      end
    end
  end

  describe "#get_network_interface_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, nic_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_network_interface_by_name(nic_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body.to_json,
          :headers => {})
        stub_request(:get, load_balancer_uri).to_return(
          :status => 200,
          :body => load_balancer_response_body,
          :headers => {})
        stub_request(:get, nic_uri).to_return(
          :status => 200,
          :body => nic_response_body,
          :headers => {})
        expect(
          azure_client2.get_network_interface_by_name(nic_name)
        ).to eq(fake_nic)
      end
    end
  end

  describe "#get_network_subnet_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, network_subnet_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_network_subnet_by_name(resource_group_name, vnet_name, subnet_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, network_subnet_uri).to_return(
          :status => 200,
          :body => network_subnet_response_body,
          :headers => {})
        expect(
          azure_client2.get_network_subnet_by_name(resource_group_name, vnet_name, subnet_name)
        ).to eq(fake_network_subnet)

      end
    end
  end

  describe "#get_storage_account_by_name" do
    let(:storage_account_name) { "foo" }
    let(:storage_account_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}?api-version=#{api_version}" }

    context "if get operation returns retryable error code (returns 429)" do
      it "should raise error if it always returns 429" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).to_return(
          {
            :status => 429,
            :body => '',
            :headers => {}
          }
        )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
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
        stub_request(:get, storage_account_uri).to_return(
          {
            :status => 429,
            :body => '',
            :headers => {}
          },
          {
            :status => 200,
            :body => '',
            :headers => {}
          }
        )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should not raise error if it raises Net::OpenTimeout at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(Net::OpenTimeout.new).then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should not raise error if it raises Net::ReadTimeout at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(Net::ReadTimeout.new).then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should not raise error if it raises Errno::ECONNRESET at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(Errno::ECONNRESET.new).then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should not raise error if it raises OpenSSL::SSL::SSLError with specified message 'SSL_connect' at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(OpenSSL::SSL::SSLError.new(ERROR_MSG_OPENSSL_RESET)).then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should not raise error if it raises OpenSSL::X509::StoreError with specified message 'SSL_connect' at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(OpenSSL::X509::StoreError.new(ERROR_MSG_OPENSSL_RESET)).then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end

      it "should raise OpenSSL::SSL::SSLError if it raises OpenSSL::SSL::SSLError without specified message 'SSL_connect'" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(OpenSSL::SSL::SSLError.new)

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.to raise_error OpenSSL::SSL::SSLError
      end

      it "should raise OpenSSL::X509::StoreError if it raises OpenSSL::X509::StoreError without specified message 'SSL_connect'" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise(OpenSSL::X509::StoreError.new)

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.to raise_error OpenSSL::X509::StoreError
      end

      it "should not raise error if it raises 'SocketError: Hostname not known' at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise('SocketError: Hostname not known').then.
            to_return(
              {
                :status => 200,
                :body => '',
                :headers => {}
              }
            )

        expect {
          azure_client2.get_storage_account_by_name(storage_account_name)
        }.not_to raise_error
      end
    end

    context "when token is valid, getting response succeeds" do
      context "if response body is null" do
        it "should return null" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:get, storage_account_uri).to_return(
            :status => 200,
            :body => '',
            :headers => {})
          expect(
            azure_client2.get_storage_account_by_name(storage_account_name)
          ).to be_nil
        end
      end

      context "if response body is not null" do
        context "when response body includes all endpoints" do
          let(:response_body) {
            {
              "id" => "fake-id",
              "name" => "fake-name",
              "location" => "fake-location",
              "properties" => {
                "provisioningState" => "fake-state",
                "accountType" => "fake-type",
                "primaryEndpoints" => {
                  "blob" => "fake-blob-endpoint",
                  "table" => "fake-table-endpoint",
                }
              }
            }.to_json
          }
          let(:fake_storage_account) {
            {
              :id => "fake-id",
              :name => "fake-name",
              :location => "fake-location",
              :provisioning_state => "fake-state",
              :account_type => "fake-type",
              :storage_blob_host => "fake-blob-endpoint",
              :storage_table_host => "fake-table-endpoint"
            }
          }

          it "should return resource including both blob endpoint and table endpoint" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:get, storage_account_uri).to_return(
              :status => 200,
              :body => response_body,
              :headers => {})
            expect(
              azure_client2.get_storage_account_by_name(storage_account_name)
            ).to eq(fake_storage_account)
          end
        end

        context "when response body only includes blob endpoint" do
          let(:response_body) {
            {
              "id" => "fake-id",
              "name" => "fake-name",
              "location" => "fake-location",
              "properties" => {
                "provisioningState" => "fake-state",
                "accountType" => "fake-type",
                "primaryEndpoints" => {
                  "blob" => "fake-blob-endpoint"
                }
              }
            }.to_json
          }
          let(:fake_storage_account) {
            {
              :id => "fake-id",
              :name => "fake-name",
              :location => "fake-location",
              :provisioning_state => "fake-state",
              :account_type => "fake-type",
              :storage_blob_host => "fake-blob-endpoint"
            }
          }

          it "should return resource only including blob endpoint" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:get, storage_account_uri).to_return(
              :status => 200,
              :body => response_body,
              :headers => {})
            expect(
              azure_client2.get_storage_account_by_name(storage_account_name)
            ).to eq(fake_storage_account)
          end
        end
      end
    end
  end

  describe "#list_storage_accounts" do
    let(:storage_accounts_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Storage/storageAccounts?api-version=#{api_version}" }

    context "when token is valid, getting response succeeds" do
      context "if response body is null" do
        it "should return empty" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:get, storage_accounts_uri).to_return(
            :status => 200,
            :body => '',
            :headers => {})
          expect(
            azure_client2.list_storage_accounts()
          ).to eq([])
        end
      end

      context "if response body is not null" do
        let(:response_body) {
          {
            "value" => [
              {
                "id" => "fake-id1",
                "name" => "fake-name1",
                "location" => "fake-location",
                "tags" => {
                  "foo" => "bar1",
                },
                "properties" => {
                  "provisioningState" => "fake-state",
                  "accountType" => "fake-type",
                  "primaryEndpoints" => {
                    "blob" => "fake-blob-endpoint",
                    "table" => "fake-table-endpoint",
                  }
                }
              }, {
                "id" => "fake-id2",
                "name" => "fake-name2",
                "location" => "fake-location",
                "tags" => {
                  "foo" => "bar2"
                },
                "properties" => {
                  "provisioningState" => "fake-state",
                  "accountType" => "fake-type",
                  "primaryEndpoints" => {
                    "blob" => "fake-blob-endpoint"
                  }
                }
              }
            ]
          }.to_json
        }
        let(:fake_storage_accounts) {
          [
            {
              :id => "fake-id1",
              :name => "fake-name1",
              :location => "fake-location",
              :tags => {
                "foo" => "bar1",
              },
              :provisioning_state => "fake-state",
              :account_type => "fake-type",
              :storage_blob_host => "fake-blob-endpoint",
              :storage_table_host => "fake-table-endpoint"
            }, {
              :id => "fake-id2",
              :name => "fake-name2",
              :location => "fake-location",
              :tags => {
                "foo" => "bar2",
              },
              :provisioning_state => "fake-state",
              :account_type => "fake-type",
              :storage_blob_host => "fake-blob-endpoint"
            }
          ]
        }

        it "should return resource including both blob endpoint and table endpoint" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:get, storage_accounts_uri).to_return(
            :status => 200,
            :body => response_body,
            :headers => {})
          expect(
            azure_client2.list_storage_accounts()
          ).to eq(fake_storage_accounts)
        end
      end
    end
  end

  describe "#get_virtual_machine_by_name" do
    let(:api_version) { AZURE_API_VERSION }
    let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
    let(:vm_name) { "fake-vm-name" }
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }

    context "when the response body is null" do
      it "should return null" do
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_virtual_machine_by_name(vm_name)
        ).to be_nil
      end
    end

    context "when the response body is not null" do
      context "when the vm is using the unmanaged disks" do
        let(:response_body) {
          {
            "id"          => "fake-id",
            "name"        => "fake-name",
            "location"    => "fake-location",
            "tags"        => {},
            "properties"  => {
              "provisioningState"  => "foo",
              "hardwareProfile" => { "vmSize" => "bar" },
              "storageProfile" => {
                "osDisk"  => {
                  "name" => "foo",
                  "vhd" => { "uri" => "foo" },
                  "caching" => "bar",
                  "diskSizeGb" => 1024
                },
                "dataDisks" => [
                  {
                    "name" => "foo",
                    "lun"  => 0,
                    "vhd" => { "uri" => "foo" },
                    "caching" => "bar",
                    "diskSizeGb" => 1024
                  }
                ]
              },
              "networkProfile" => {
                "networkInterfaces" => [
                  {
                    "id" => nic_id
                  }
                ]
              }
            }
          }.to_json
        }

        let(:fake_vm) {
          {
            :id          => "fake-id",
            :name        => "fake-name",
            :location    => "fake-location",
            :tags        => {},
            :provisioning_state  => "foo",
            :vm_size => "bar",
            :os_disk  => {
               :name => "foo",
               :uri => "foo",
               :caching => "bar",
               :size => 1024
            },
            :data_disks => [{
               :name => "foo",
               :lun  => 0,
               :uri  => "foo",
               :caching => "bar",
               :size => 1024
            }],
            :network_interfaces => [fake_nic]
          }
        }

        it "should return the resource with the unmanaged disk" do
          stub_request(:get, public_ip_uri).to_return(
            :status => 200,
            :body => public_ip_response_body.to_json,
            :headers => {})
          stub_request(:get, load_balancer_uri).to_return(
            :status => 200,
            :body => load_balancer_response_body,
            :headers => {})
          stub_request(:get, nic_uri).to_return(
            :status => 200,
            :body => nic_response_body,
            :headers => {})
          stub_request(:get, vm_uri).to_return(
            :status => 200,
            :body => response_body,
            :headers => {})
          expect(
            azure_client2.get_virtual_machine_by_name(vm_name)
          ).to eq(fake_vm)
        end
      end

      context "when the vm is using the managed disks" do
        let(:response_body) {
          {
            "id"          => "fake-id",
            "name"        => "fake-name",
            "location"    => "fake-location",
            "tags"        => {},
            "properties"  => {
              "provisioningState"  => "foo",
              "hardwareProfile" => { "vmSize" => "bar" },
              "storageProfile" => {
                "osDisk"  => {
                  "name" => "foo",
                  "caching" => "bar",
                  "diskSizeGb" => 1024,
                  "managedDisk" => {
                    "id" => "fake-disk-id",
                    "storageAccountType" => "fake-storage-account-type"
                  }
                },
                "dataDisks" => [
                  {
                    "name" => "foo",
                    "lun"  => 0,
                    "caching" => "bar",
                    "diskSizeGb" => 1024,
                    "managedDisk" => {
                      "id" => "fake-disk-id",
                      "storageAccountType" => "fake-storage-account-type"
                    }
                  }
                ]
              },
              "networkProfile" => {
                "networkInterfaces" => [
                  {
                    "id" => nic_id
                  }
                ]
              }
            }
          }.to_json
        }

        let(:fake_vm) {
          {
            :id          => "fake-id",
            :name        => "fake-name",
            :location    => "fake-location",
            :tags        => {},
            :provisioning_state  => "foo",
            :vm_size => "bar",
            :os_disk  => {
               :name => "foo",
               :caching => "bar",
               :size => 1024,
               :managed_disk => {
                 :id => "fake-disk-id",
                 :storage_account_type => "fake-storage-account-type"
               }
            },
            :data_disks => [{
               :name => "foo",
               :lun  => 0,
               :caching => "bar",
               :size => 1024,
               :managed_disk => {
                 :id => "fake-disk-id",
                 :storage_account_type => "fake-storage-account-type"
               }
            }],
            :network_interfaces => [fake_nic]
          }
        }

        it "should return the resource with the unmanaged disk" do
          stub_request(:get, public_ip_uri).to_return(
            :status => 200,
            :body => public_ip_response_body.to_json,
            :headers => {})
          stub_request(:get, load_balancer_uri).to_return(
            :status => 200,
            :body => load_balancer_response_body,
            :headers => {})
          stub_request(:get, nic_uri).to_return(
            :status => 200,
            :body => nic_response_body,
            :headers => {})
          stub_request(:get, vm_uri).to_return(
            :status => 200,
            :body => response_body,
            :headers => {})
          expect(
            azure_client2.get_virtual_machine_by_name(vm_name)
          ).to eq(fake_vm)
        end
      end
    end
  end

  describe "#get_network_security_group_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, nsg_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_network_security_group_by_name(resource_group_name, nsg_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, nsg_uri).to_return(
          :status => 200,
          :body => nsg_response_body,
          :headers => {})
        expect(
          azure_client2.get_network_security_group_by_name(resource_group_name, nsg_name)
        ).to eq(fake_nsg)
      end
    end
  end
end
