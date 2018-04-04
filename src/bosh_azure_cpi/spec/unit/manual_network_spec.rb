require "spec_helper"

describe Bosh::AzureCloud::ManualNetwork do
  let(:azure_properties) { mock_azure_properties }

  context "when all properties are specified" do
    let(:private_ip) { "fake-private-ip" }
    let(:dns) { "fake-dns" }
    let(:vnet_name) { "fake-vnet-name" }
    let(:subnet_name) { "fake-subnet-name" }
    let(:rg_name) { "fake-resource-group-name" }
    let(:nsg_name) { "fake-nsg-name" }
    let(:asg_names) { ["fake-asg-name-1", "fake-asg-name-2"] }
    let(:network_spec) {
      {
        "ip" => private_ip,
        "default" => ["dns", "gateway"],
        "dns" => dns,
        "cloud_properties" => {
          "virtual_network_name"        => vnet_name,
          "subnet_name"                 => subnet_name,
          "resource_group_name"         => rg_name,
          "security_group"              => nsg_name,
          "application_security_groups" => asg_names,
          "ip_forwarding"               => true
        }
      }
    }

    it "should return properties with right values" do
      network = Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
      expect(network.private_ip).to eq(private_ip)
      expect(network.resource_group_name).to eq(rg_name)
      expect(network.virtual_network_name).to eq(vnet_name)
      expect(network.subnet_name).to eq(subnet_name)
      expect(network.security_group).to eq(nsg_name)
      expect(network.application_security_groups).to eq(asg_names)
      expect(network.ip_forwarding).to eq(true)
      expect(network.dns).to eq(dns)
      expect(network.has_default_dns?).to be true
      expect(network.has_default_gateway?).to be true
    end
  end

  context "when missing cloud_properties" do
    let(:network_spec) {
      {
        "fake-key" => "fake-value"
      }
    }

    it "should raise an error" do
      expect {
        Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
      }.to raise_error(/cloud_properties required for manual network/)
    end
  end

  context "when virtual_network_name is invalid" do
    context "when missing virtual_network_name" do
      let(:network_spec) {
        {
          "cloud_properties"=>{
            "subnet_name"=>"bar"
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/virtual_network_name required for manual network/)
      end
    end

    context "when virtual_network_name is nil" do
      let(:network_spec) {
        {
          "cloud_properties"=>{
            "virtual_network_name"=>nil,
            "subnet_name"=>"bar"
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/virtual_network_name required for manual network/)
      end
    end
  end

  context "when subnet_name is invalid" do
    context "when missing subnet_name" do
      let(:network_spec) {
        {
          "cloud_properties"=>{
            "virtual_network_name"=>"foo"
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/subnet_name required for manual network/)
      end
    end

    context "when subnet_name is nil" do
      let(:network_spec) {
        {
          "cloud_properties"=>{
            "virtual_network_name"=>"foo",
            "subnet_name"=>nil
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/subnet_name required for manual network/)
      end
    end
  end

  context "when ip is invalid" do
    context "when missing ip" do
      let(:network_spec) {
        {
          "cloud_properties"=>{
            "virtual_network_name"=>"foo",
            "subnet_name"=>"bar"
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/ip address required for manual network/)
      end
    end

    context "when ip is nil" do
      let(:network_spec) {
        {
          "ip" => nil,
          "cloud_properties"=>{
            "virtual_network_name"=>"foo",
            "subnet_name"=>"bar"
          }
        }
      }

      it "should raise an error" do
        expect {
          Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
        }.to raise_error(/ip address required for manual network/)
      end
    end
  end

  context "when optional cloud properties are not specified" do
    let(:network_spec) {
      {
        "ip" => "fake-ip",
        "cloud_properties"=>{
          "virtual_network_name"=>"foo",
          "subnet_name"=>"bar"
        }
      }
    }

    it "should return default values for the optional cloud properties" do
      network = Bosh::AzureCloud::ManualNetwork.new(azure_properties, "default", network_spec)
      expect(network.security_group).to be_nil
      expect(network.application_security_groups).to eq([])
      expect(network.ip_forwarding).to be false
      expect(network.resource_group_name).to eq(azure_properties["resource_group_name"])
      expect(network.dns).to be_nil
      expect(network.has_default_dns?).to be false
      expect(network.has_default_dns?).to be false
    end
  end
end
