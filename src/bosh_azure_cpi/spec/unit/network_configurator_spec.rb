require "spec_helper"

describe Bosh::AzureCloud::NetworkConfigurator do

  let(:dynamic) {
    {
      "type" => "dynamic",
      "cloud_properties" =>
        {
          "subnet_name" => "bar",
          "virtual_network_name" => "foo"
        }
    }
  }
  let(:manual) {
    {
      "type" => "manual",
      "cloud_properties" =>
        {
          "resource_group_name" => "fake-rg",
          "subnet_name" => "bar",
          "virtual_network_name" => "foo",
          "security_group" => "fake-nsg"
        }
    }
  }
  let(:vip) {
    {
      "type" => "vip"
    }
  }

  it "should raise an error if the spec isn't a hash" do
    expect {
      Bosh::AzureCloud::NetworkConfigurator.new("foo")
    }.to raise_error ArgumentError
  end

  describe "#public_ip" do
    it "should extract public ip address from vip network when there's also manual network" do
      spec = {}
      spec["network_a"] = vip
      spec["network_a"]["ip"] = "10.0.0.1"
      spec["network_b"] = manual
      spec["network_b"]["ip"] = "10.0.0.2"      

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.public_ip).to eq("10.0.0.1")
    end     
    
    it "should extract public ip address from vip network when there's also dynamic network" do
      spec = {}
      spec["network_a"] = vip
      spec["network_a"]["ip"] = "10.0.0.1"
      spec["network_b"] = dynamic
      spec["network_b"]["ip"] = "10.0.0.2"      

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.public_ip).to eq("10.0.0.1")
    end     
  end

  describe "#private_ip" do
    it "should extract private ip address for manual network" do
      spec = {}
      spec["network_a"] = manual
      spec["network_a"]["ip"] = "10.0.0.1"

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to eq("10.0.0.1")
    end

    it "should extract private ip address from manual network when there's also vip network" do
      spec = {}
      spec["network_a"] = vip
      spec["network_a"]["ip"] = "10.0.0.1"
      spec["network_b"] = manual
      spec["network_b"]["ip"] = "10.0.0.2"      

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to eq("10.0.0.2")
    end     
    
    it "should not extract private ip address for dynamic network" do
      spec = {}
      spec["network_a"] = dynamic
      spec["network_a"]["ip"] = "10.0.0.1"

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to be_nil
    end     

    it "should not extract private ip address from dynamic network when there's also vip network" do
      spec = {}
      spec["network_a"] = vip
      spec["network_a"]["ip"] = "10.0.0.1"
      spec["network_b"] = dynamic
      spec["network_b"]["ip"] = "10.0.0.2"      

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.private_ip).to be_nil
    end     
  end
  
  describe "network types" do
    it "should not raise an error if one dynamic network are defined" do
      network_spec = {
        "network1" => dynamic
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.not_to raise_error
    end

    it "should not raise an error if one manual networks are defined" do
      network_spec = {
        "network1" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.not_to raise_error
    end

    it "should raise an error if both dynamic and manual networks are defined" do
      network_spec = {
        "network1" => dynamic,
        "network2" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if neither dynamic nor manual networks are defined" do
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new("network1" => vip)
      }.to raise_error Bosh::Clouds::CloudError, "Exactly one dynamic or manual network must be defined"
    end

    it "should raise an error if multiple vip networks are defined" do
      network_spec = {
        "network1" => vip,
        "network2" => vip
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "More than one vip network for `network2'"
    end

    it "should raise an error if multiple dynamic networks are defined" do
      network_spec = {
        "network1" => dynamic,
        "network2" => dynamic
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if multiple manual networks are defined" do
      network_spec = {
        "network1" => manual,
        "network2" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "Must have exactly one dynamic or manual network per instance"
    end

    it "should raise an error if an illegal network type is used" do
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new("network1" => {"type" => "foo"})
      }.to raise_error Bosh::Clouds::CloudError, "Invalid network type `foo' for Azure, " \
                        "can only handle `dynamic', `vip', or `manual' network types"
    end
  end

  describe  "uncomplete network spec" do
    it "should raise an error if subnet_name is missed in one dynamic network" do
      dynamic["cloud_properties"].delete("subnet_name")
      network_spec = {
          "network1" => dynamic
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "subnet_name required for dynamic network"
    end

    it "should raise an error if virtual_network_name is missed in one dynamic network" do
      dynamic["cloud_properties"].delete("virtual_network_name")
      network_spec = {
        "network1" => dynamic
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "virtual_network_name required for dynamic network"
    end

    it "should raise an error if subnet_name is missed in one manual network" do
      manual["cloud_properties"].delete("subnet_name")
      network_spec = {
        "network1" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "subnet_name required for manual network"
    end

    it "should raise an error if virtual_network_name is missed in one manual network" do
      manual["cloud_properties"].delete("virtual_network_name")
      network_spec = {
        "network1" => manual
      }
      expect {
        Bosh::AzureCloud::NetworkConfigurator.new(network_spec)
      }.to raise_error Bosh::Clouds::CloudError, "virtual_network_name required for manual network"
    end
  end

  describe "#security_group" do
    it "should return network security group when spec contains security_group" do
      spec = {}
      spec["network_a"] = manual
      spec["network_b"] = vip

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.security_group).to eq("fake-nsg")
    end

    it "should return nil when spec does not contain security_group" do
      spec = {}
      spec["network_a"] = {
        "type" => "manual",
        "cloud_properties" => {
          "subnet_name" => "bar",
          "virtual_network_name" => "foo"
        }
      }
      spec["network_b"] = vip

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.security_group).to be_nil
    end
  end

  describe "#resource_group_name" do
    it "should return resource group name when non-vip network spec contains resource_group_name" do
      spec = {}
      spec["network_a"] = manual
      spec["network_b"] = vip

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.resource_group_name).to eq("fake-rg")
    end

    it "should return nil when non-vip network spec does not contain resource_group_name" do
      spec = {}
      spec["network_a"] = {
        "type" => "manual",
        "cloud_properties" => {
          "subnet_name" => "bar",
          "virtual_network_name" => "foo"
        }
      }
      spec["network_b"] = vip

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.resource_group_name).to be_nil
    end

    it "should return resource group name when vip network spec contains resource_group_name" do
      spec = {}
      spec["network_a"] = manual
      spec["network_b"] = {
        "type" => "vip",
        "cloud_properties" => {
          "resource_group_name" => "fake-rg-for-public-ip"
        }
      }

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.resource_group_name("vip")).to eq("fake-rg-for-public-ip")
    end

    it "should return nil when vip network spec does not contain resource_group_name" do
      spec = {}
      spec["network_a"] = manual
      spec["network_b"] = vip

      nc = Bosh::AzureCloud::NetworkConfigurator.new(spec)
      expect(nc.resource_group_name("vip")).to be_nil
    end
  end
end
