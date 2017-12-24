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
  let(:default_resource_group_name) { mock_azure_properties['resource_group_name'] }
  let(:resource_group_name) { "fake-resource-group-name" }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  # Public IP
  let(:public_ip_name) { "fake-name" }
  let(:public_ip_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}" }
  let(:public_ip_uri) { "https://management.azure.com/#{public_ip_id}?api-version=#{api_version_network}" }
  let(:public_ip_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "zones" => ["fake-zone"],
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
      :zone => "fake-zone",
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
  let(:load_balancer_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group_name}/providers/Microsoft.Network/loadBalancers/#{load_balancer_name}" }
  let(:load_balancer_uri) { "https://management.azure.com/#{load_balancer_id}?api-version=#{api_version_network}" }
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

  # Application Gateway
  let(:application_gateway_name) { "fake-name" }
  let(:application_gateway_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group_name}/providers/Microsoft.Network/applicationGateways/#{application_gateway_name}" }
  let(:application_gateway_uri) { "https://management.azure.com/#{application_gateway_id}?api-version=#{api_version_network}" }
  let(:application_gateway_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "provisioningState" => "fake-state",
        "backendAddressPools" => [{
          "id" => "fake-id"
        }]
      }
    }.to_json
  }
  let(:fake_application_gateway) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :tags => "fake-tags",
      :backend_address_pools => [
        {
          :id => "fake-id"
        }
      ]
    }
  }

  # Network Interface
  let(:nic_name) { "fake-name" }
  let(:nic_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/networkInterfaces/#{nic_name}" }
  let(:nic_uri) { "https://management.azure.com/#{nic_id}?api-version=#{api_version_network}" }
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
              "privateIPAllocationMethod" => "Dynamic"
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
      :private_ip_allocation_method => "Dynamic"
    }
  }

  # Virtual Network
  let(:vnet_name) { "fake-vnet-name" }
  let(:vnet_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/virtualNetworks/#{vnet_name}?api-version=#{api_version_network}" }
  let(:vnet_response_body) {
    {
      "id" => "fake-vnet-id",
      "name" => "fake-vnet-name",
      "location" => "fake-location",
      "properties" => {
        "provisioningState" => "fake-vnet-state",
        "addressSpace" => "fake-address-space",
        "subnets" => [
          {
            "name" => "fake-subnet-name",
            "id" => "fake-subnet-id",
            "properties" => {
              "provisioningState" => "fake-subnet-state",
              "addressPrefix" => "fake-address-prefix"
            }
          }
        ]
      }
    }.to_json
  }
  let(:fake_vnet) {
    {
      :id => "fake-vnet-id",
      :name => "fake-vnet-name",
      :location => "fake-location",
      :provisioning_state => "fake-vnet-state",
      :address_space => "fake-address-space",
      :subnets => [
        {
          :id => "fake-subnet-id",
          :name => "fake-subnet-name",
          :provisioning_state => "fake-subnet-state",
          :address_prefix => "fake-address-prefix"
        }
      ]
    }
  }

  # Subnet
  let(:vnet_name) { "fake-name" }
  let(:subnet_name) { "bar" }
  let(:network_subnet_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/virtualNetworks/#{vnet_name}/subnets/#{subnet_name}?api-version=#{api_version_network}" }
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
  let(:nsg_name) { "fake-nsg-name" }
  let(:nsg_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/networkSecurityGroups/#{nsg_name}" }
  let(:nsg_uri) { "https://management.azure.com/#{nsg_id}?api-version=#{api_version_network}" }
  let(:nsg_response_body) {
    {
      "id" => "fake-id",
      "name" => nsg_name,
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
      :name => nsg_name,
      :location => "fake-location",
      :tags => "fake-tags",
      :provisioning_state => "fake-state"
    }
  }

  # Application Security Group
  let(:asg_name) { "fake-asg-name" }
  let(:asg_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/applicationSecurityGroups/#{asg_name}" }
  let(:asg_uri) { "https://management.azure.com/#{asg_id}?api-version=#{api_version_network}" }
  let(:asg_response_body) {
    {
      "id" => "fake-id",
      "name" => asg_name,
      "location" => "fake-location",
      "tags" => "fake-tags",
      "properties" => {
        "provisioningState" => "fake-state"
      }
    }.to_json
  }
  let(:fake_asg) {
    {
      :id => "fake-id",
      :name => asg_name,
      :location => "fake-location",
      :tags => "fake-tags",
      :provisioning_state => "fake-state"
    }
  }

  let(:storage_account_name) { "fake-name" }

  before do
    stub_request(:post, token_uri).to_return(
      :status => 200,
      :body => {
        "access_token" => valid_access_token,
        "expires_on" => expires_on
      }.to_json,
      :headers => {})
  end

  describe "#list_available_virtual_machine_sizes" do
    let(:location) { "fake-location" }
    let(:list_available_virtual_machine_sizes_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/providers/Microsoft.Compute/locations/#{location}/vmSizes?api-version=#{AZURE_RESOURCE_PROVIDER_COMPUTE}" }
    let(:list_available_virtual_machine_sizes_response_body) {
      {
        "value" => [
          {
            "name": "Standard_A0",
            "numberOfCores": 1,
            "osDiskSizeInMB": 130048,
            "resourceDiskSizeInMB": 20480,
            "memoryInMB": 768,
            "maxDataDiskCount": 1
          },
          {
            "name": "Standard_A1",
            "numberOfCores": 1,
            "osDiskSizeInMB": 130048,
            "resourceDiskSizeInMB": 71680,
            "memoryInMB": 1792,
            "maxDataDiskCount": 2
          }
        ]
      }
    }
    let(:fake_vm_size_list) {
      [
        {
          "name": "Standard_A0",
          "number_of_cores": 1,
          "memory_in_mb": 768
        },
        {
          "name": "Standard_A1",
          "number_of_cores": 1,
          "memory_in_mb": 1792
        }
      ]
    }
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, list_available_virtual_machine_sizes_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.list_available_virtual_machine_sizes(location)
        ).to eq([])
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, list_available_virtual_machine_sizes_uri).to_return(
          :status => 200,
          :body => list_available_virtual_machine_sizes_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.list_available_virtual_machine_sizes(location)
        ).to eq(fake_vm_size_list)
      end
    end
  end

  describe "#get_public_ip_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_public_ip_by_name(resource_group_name, public_ip_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.get_public_ip_by_name(resource_group_name, public_ip_name)
        ).to eq(fake_public_ip)
      end
    end
  end

  describe "#list_public_ips" do
    let(:list_public_ips_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/publicIPAddresses?api-version=#{api_version_network}" }
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

  describe "#get_application_gateway_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, application_gateway_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_application_gateway_by_name(application_gateway_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, application_gateway_uri).to_return(
          :status => 200,
          :body => application_gateway_response_body,
          :headers => {})
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body.to_json,
          :headers => {})
        expect(
          azure_client2.get_application_gateway_by_name(application_gateway_name)
        ).to eq(fake_application_gateway)
      end
    end
  end

  describe "#get_network_interface_by_name" do
    context "when the response body is null" do
      it "should return null" do
        stub_request(:get, nic_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
        ).to be_nil
      end
    end

    context "when the response body is not null" do
      context "when the network interface doesn't bind to other resources" do
        it "should return the resource" do
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
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end

      context "when the network interface is bound to public ip" do
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
                    }
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
            :public_ip => fake_public_ip
          }
        }
        it "should return the network interface with public ip" do
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
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end

      context "when the network interface is bound to load balancer" do
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
            :load_balancer => fake_load_balancer
          }
        }
        it "should return the network interface with load balancer" do
          # get_load_balancer needs get_public_ip
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
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end

      context "when the network interface is bound to application gateway" do
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
                    "applicationGatewayBackendAddressPools" => [{
                      "id" => application_gateway_id
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
            :application_gateway => fake_application_gateway
          }
        }
        it "should return the network interface with load balancer" do
          # get_load_balancer needs get_public_ip
          stub_request(:get, public_ip_uri).to_return(
            :status => 200,
            :body => public_ip_response_body.to_json,
            :headers => {})
          stub_request(:get, application_gateway_uri).to_return(
            :status => 200,
            :body => application_gateway_response_body,
            :headers => {})
          stub_request(:get, nic_uri).to_return(
            :status => 200,
            :body => nic_response_body,
            :headers => {})
          expect(
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end

      context "when the network interface is bound to network security group" do
        let(:nic_response_body) {
          {
            "id" => "fake-id",
            "name" => "fake-name",
            "location" => "fake-location",
            "tags" => "fake-tags",
            "properties" => {
              "provisioningState" => "fake-state",
              "networkSecurityGroup" => {
                "id" => nsg_id
              },
              "dnsSettings" => {
                "dnsServers" => ["168.63.129.16"]
              },
              "ipConfigurations" => [
                {
                  "id" => "fake-id",
                  "properties" => {
                    "privateIPAddress" => "10.0.0.100",
                    "privateIPAllocationMethod" => "Dynamic"
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
            :network_security_group => fake_nsg,
            :dns_settings => ["168.63.129.16"],
            :ip_configuration_id => "fake-id",
            :private_ip => "10.0.0.100",
            :private_ip_allocation_method => "Dynamic"
          }
        }
        it "should return the network interface with network security group" do
          stub_request(:get, nsg_uri).to_return(
            :status => 200,
            :body => nsg_response_body,
            :headers => {})
          stub_request(:get, nic_uri).to_return(
            :status => 200,
            :body => nic_response_body,
            :headers => {})
          expect(
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end

      context "when the network interface is bound to application security group" do
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
                    "applicationSecurityGroups" => [
                      "id" => asg_id
                    ]
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
            :application_security_groups => [fake_asg]
          }
        }
        it "should return the network interface with public ip" do
          stub_request(:get, asg_uri).to_return(
            :status => 200,
            :body => asg_response_body,
            :headers => {})
          stub_request(:get, nic_uri).to_return(
            :status => 200,
            :body => nic_response_body,
            :headers => {})
          expect(
            azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          ).to eq(fake_nic)
        end
      end
    end
  end

  describe "#get_virtual_network_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, vnet_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_virtual_network_by_name(resource_group_name, vnet_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, vnet_uri).to_return(
          :status => 200,
          :body => vnet_response_body,
          :headers => {})
        expect(
          azure_client2.get_virtual_network_by_name(resource_group_name, vnet_name)
        ).to eq(fake_vnet)

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
    let(:storage_account_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group_name}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}?api-version=#{api_version}" }

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

      it "should not raise error if it raises 'Hostname not known' at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise('Hostname not known').then.
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

      it "should not raise error if it raises 'Connection refused - connect(2) for \"xx.xxx.xxx.xx\" port 443' at the first time but returns 200 at the second time" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, storage_account_uri).
            to_raise('Connection refused - connect(2) for \"xx.xxx.xxx.xx\" port 443').then.
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
              "tags" => {
                "foo" => "bar"
              },
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
              :tags => {
                "foo" => "bar"
              },
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
              "tags" => {
                "foo" => "bar"
              },
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
              :tags => {
                "foo" => "bar"
              },
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
    let(:storage_accounts_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group_name}/providers/Microsoft.Storage/storageAccounts?api-version=#{api_version}" }

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
          azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
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
               :size => 1024,
               :disk_bosh_id => "foo"
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
          stub_request(:get, application_gateway_uri).to_return(
            :status => 200,
            :body => application_gateway_response_body,
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
            azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
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
               },
               :disk_bosh_id => "foo"
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
          stub_request(:get, application_gateway_uri).to_return(
            :status => 200,
            :body => application_gateway_response_body,
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
            azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
          ).to eq(fake_vm)
        end
      end

      context "when the vm has tags for bosh_disk_id" do
        let(:response_body) {
          {
            "id"          => "fake-id",
            "name"        => "fake-name",
            "location"    => "fake-location",
            "tags"        => {
              "disk-id-foo" => "fake-disk-bosh-id"
            },
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
            :tags        => {
              "disk-id-foo" => "fake-disk-bosh-id"
            },
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
               },
               :disk_bosh_id => "fake-disk-bosh-id"
            }],
            :network_interfaces => [fake_nic]
          }
        }

        it "should return the resource using using tag as disk_bosh_id" do
          stub_request(:get, public_ip_uri).to_return(
            :status => 200,
            :body => public_ip_response_body.to_json,
            :headers => {})
          stub_request(:get, load_balancer_uri).to_return(
            :status => 200,
            :body => load_balancer_response_body,
            :headers => {})
          stub_request(:get, application_gateway_uri).to_return(
            :status => 200,
            :body => application_gateway_response_body,
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
            azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
          ).to eq(fake_vm)
        end
      end

      context "when the vm has diagnosticsProfile specified" do
        context "when boot diagnostics is not enabled" do
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
                  "dataDisks" => []
                },
                "networkProfile" => {
                  "networkInterfaces" => [
                    {
                      "id" => nic_id
                    }
                  ]
                },
                "diagnosticsProfile" => {
                  "bootDiagnostics" => {
                    "enabled" => false
                  }
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
              :data_disks => [],
              :network_interfaces => [fake_nic]
            }
          }

          it "should return correct value" do
            stub_request(:get, public_ip_uri).to_return(
              :status => 200,
              :body => public_ip_response_body.to_json,
              :headers => {})
            stub_request(:get, load_balancer_uri).to_return(
              :status => 200,
              :body => load_balancer_response_body,
              :headers => {})
            stub_request(:get, application_gateway_uri).to_return(
              :status => 200,
              :body => application_gateway_response_body,
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
              azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
            ).to eq(fake_vm)
          end
        end

        context "when boot diagnostics is enabled" do
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
                  "dataDisks" => []
                },
                "networkProfile" => {
                  "networkInterfaces" => [
                    {
                      "id" => nic_id
                    }
                  ]
                },
                "diagnosticsProfile" => {
                  "bootDiagnostics" => {
                    "enabled" => true,
                    "storageUri" => "fake-storage-uri"
                  }
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
              :data_disks => [],
              :network_interfaces => [fake_nic],
              :diag_storage_uri => "fake-storage-uri"
            }
          }

          it "should return correct value" do
            stub_request(:get, public_ip_uri).to_return(
              :status => 200,
              :body => public_ip_response_body.to_json,
              :headers => {})
            stub_request(:get, load_balancer_uri).to_return(
              :status => 200,
              :body => load_balancer_response_body,
              :headers => {})
            stub_request(:get, application_gateway_uri).to_return(
              :status => 200,
              :body => application_gateway_response_body,
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
              azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
            ).to eq(fake_vm)
          end
        end
      end

      context "when the vm is in a zone" do
        let(:response_body) {
          {
            "id"          => "fake-id",
            "name"        => "fake-name",
            "location"    => "fake-location",
            "tags"        => {},
            "zones"       => ["fake-zone"],
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
                "dataDisks" => []
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
            :zone        => "fake-zone",
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
            :data_disks => [],
            :network_interfaces => [fake_nic]
          }
        }

        it "should return correct value with zone" do
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
            azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)
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

  describe "#get_application_security_group_by_name" do
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, asg_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_application_security_group_by_name(resource_group_name, asg_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, asg_uri).to_return(
          :status => 200,
          :body => asg_response_body,
          :headers => {})
        expect(
          azure_client2.get_application_security_group_by_name(resource_group_name, asg_name)
        ).to eq(fake_asg)
      end
    end
  end

  describe "#get_storage_account_keys_by_name" do
    let(:storage_account_list_keys_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group_name}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}/listKeys?api-version=#{api_version}" }
    let(:storage_account_list_keys_response_body) {
      {
        "key1" => "fake-key-1",
        "key2" => "fake-key-2"
      }.to_json
    }
    let(:fake_keys) {
      [
        "fake-key-1",
        "fake-key-2"
      ]
    }

    context "when token is valid but cannot find the storage account" do
      it "should return []" do
        stub_request(:post, storage_account_list_keys_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect(
          azure_client2.get_storage_account_keys_by_name(storage_account_name)
        ).to eq([])
      end
    end

    context "when token is valid, getting response succeeds" do
      let(:logger_strio) { StringIO.new }

      context "and debug_mode is set to false" do
        let(:azure_client2) {
          Bosh::AzureCloud::AzureClient2.new(
            mock_cloud_options["properties"]["azure"],
            Logger.new(logger_strio)
          )
        }

        it "should return keys and filter keys in logs" do
          stub_request(:post, storage_account_list_keys_uri).to_return(
            :status => 200,
            :body => storage_account_list_keys_response_body,
            :headers => {})

          expect(
            azure_client2.get_storage_account_keys_by_name(storage_account_name)
          ).to eq(fake_keys)

          logs = logger_strio.string
          expect(logs.include?('fake-key-1')).to be(false)
          expect(logs.include?('fake-key-2')).to be(false)
        end
      end

      context "and debug_mode is set to true" do
        let(:azure_client2) {
          Bosh::AzureCloud::AzureClient2.new(
            mock_cloud_options["properties"]["azure"].merge({ 'debug_mode' => true }),
            Logger.new(logger_strio)
          )
        }

        it "should return keys and log keys" do
          stub_request(:post, storage_account_list_keys_uri).to_return(
            :status => 200,
            :body => storage_account_list_keys_response_body,
            :headers => {})

          expect(
            azure_client2.get_storage_account_keys_by_name(storage_account_name)
          ).to eq(fake_keys)

          logs = logger_strio.string
          expect(logs.include?('fake-key-1')).to be(true)
          expect(logs.include?('fake-key-2')).to be(true)
        end
      end
    end
  end
end
