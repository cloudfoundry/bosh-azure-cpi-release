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

  let(:valid_access_token) { "valid-access-token" }
  let(:invalid_access_token) { "invalid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }


  # Public IP
  let(:public_ip_name) { "foo" }
  let(:public_ip_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}" }
  let(:public_ip_uri) { "https://management.azure.com/#{public_ip_id}?api-version=#{api_version}" }
  let(:public_ip_response_body) {
    {
      "id" => "fake-id",
      "name" => "fake-name",
      "location" => "fake-location",
      "properties" => {
        "provisioningState" => "fake-state",
        "ipAddress" => "123.123.123.123",
        "publicIPAllocationMethod" => "Dynamic",
        "ipConfigurations" => {"id"=>"fake-id"},
        "dnsSettings" => {"domainNameLabel"=>"foo","fqdn"=>"bar"}
      }
    }.to_json
  }
  let(:fake_public_ip) {
    {
      :id => "fake-id",
      :name => "fake-name",
      :location => "fake-location",
      :provisioning_state => "fake-state",
      :ip_address => "123.123.123.123",
      :public_ip_allocation_method => "Dynamic",
      :ip_configuration_id => "fake-id",
      :domain_name_label => "foo",
      :fqdn => "bar"
    }
  }

  # Load Balancer
  let(:load_balancer_name) { "foo" }
  let(:load_balancer_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/loadBalancers/#{load_balancer_name}" }
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
  let(:nic_name) { "foo" }
  let(:nic_id) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/#{nic_name}" }
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
          "dnsServers" => ["8.8.8.8"]
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
      :dns_settings => ["8.8.8.8"],
      :ip_configuration_id => "fake-id",
      :private_ip => "10.0.0.100",
      :private_ip_allocation_method => "Dynamic",
      :public_ip => fake_public_ip,
      :load_balancer => fake_load_balancer
    }
  }

  # Subnet
  let(:vnet_name) { "foo" }
  let(:subnet_name) { "bar" }
  let(:network_subnet_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/virtualNetworks/#{vnet_name}/subnets/#{subnet_name}?api-version=#{api_version}" }
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


  before do
    stub_request(:post, token_uri).to_return(
      :status => 200,
      :body => {
        "access_token"=>valid_access_token,
        "expires_on"=>expires_on
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
          :body => public_ip_response_body,
          :headers => {})
        expect(
          azure_client2.get_public_ip_by_name(public_ip_name)
        ).to eq(fake_public_ip)
      end
    end
  end

  describe "#list_public_ips" do
    let(:list_public_ips_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses?api-version=#{api_version}" }
    let(:list_public_ips_response_body) {
      {
        "value" => [{
          "id" => "fake-id",
          "name" => "fake-name",
          "location" => "fake-location",
          "properties" => {
            "provisioningState" => "fake-state",
            "ipAddress" => "123.123.123.123",
            "publicIPAllocationMethod" => "Dynamic",
            "ipConfigurations" => {"id"=>"fake-id"},
            "dnsSettings" => {"domainNameLabel"=>"foo","fqdn"=>"bar"}
          }
        }]
      }.to_json
    }
    let(:fake_public_ip) {
      [{
        :id => "fake-id",
        :name => "fake-name",
        :location => "fake-location",
        :provisioning_state => "fake-state",
        :ip_address => "123.123.123.123",
        :public_ip_allocation_method => "Dynamic",
        :ip_configuration_id => "fake-id",
        :domain_name_label => "foo",
        :fqdn => "bar"
      }]
    }
    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, list_public_ips_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.list_public_ips()
        ).to eq([])
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, list_public_ips_uri).to_return(
          :status => 200,
          :body => list_public_ips_response_body,
          :headers => {})
        expect(
          azure_client2.list_public_ips()
        ).to eq(fake_public_ip)
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
          :body => public_ip_response_body,
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
          :body => public_ip_response_body,
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
          azure_client2.get_network_subnet_by_name(vnet_name, subnet_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, network_subnet_uri).to_return(
          :status => 200,
          :body => network_subnet_response_body,
          :headers => {})
        expect(
          azure_client2.get_network_subnet_by_name(vnet_name, subnet_name)
        ).to eq(fake_network_subnet)
      end
    end
  end

  describe "#get_storage_account_by_name" do
    let(:storage_account_name) { "foo" }
    let(:storage_account_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Storage/storageAccounts/#{storage_account_name}?api-version=#{api_version}" }
    let(:response_body) {
      {
        "id" => "fake-id",
        "name" => "fake-name",
        "location" => "fake-location",
        "properties" => {
          "provisioningState" => "fake-state",
          "accountType" => "fake-type",
          "primaryEndpoints" => "fake-endpoints"
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
        :primary_endpoints => "fake-endpoints"
      }
    }

    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
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

      it "should return the resource if response body is not null" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token"=>valid_access_token,
            "expires_on"=>expires_on
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

  describe "#get_virtual_machine_by_name" do
    let(:vm_name) { "fake-vm-name" }
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version}" }

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
              "caching" => "bar"
            },
            "dataDisks" => [
              {
                "name" => "foo",
                "lun"  => 0,
                "vhd" => { "uri" => "foo" },
                "caching" => "bar"
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
        :size => "bar",
        :os_disk  => {
           :name => "foo",
           :uri => "foo",
           :caching => "bar"
        },
        :data_disks => [{
           :name => "foo",
           :lun  => 0,
           :uri  => "foo",
           :caching => "bar"
        }],
        :network_interface => fake_nic
      }
    }

    context "when token is valid, getting response succeeds" do
      it "should return null if response body is null" do
        stub_request(:get, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {})
        expect(
          azure_client2.get_virtual_machine_by_name(vm_name)
        ).to be_nil
      end

      it "should return the resource if response body is not null" do
        stub_request(:get, public_ip_uri).to_return(
          :status => 200,
          :body => public_ip_response_body,
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
