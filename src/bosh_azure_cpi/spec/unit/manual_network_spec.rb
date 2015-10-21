require "spec_helper"

describe Bosh::AzureCloud::ManualNetwork do
  let(:network_spec) {{}}

  it "should set the IP in manual networking" do
    network_spec = {"ip"=>"172.20.214.10",
                    "netmask"=>"255.255.254.0",
                    "cloud_properties"=>{"subnet_name"=>"foo","virtual_network_name"=>"bar"},
                    "default"=>["dns", "gateway"],
                    "dns"=>["172.22.22.153"],
                    "gateway"=>"172.20.214.1",
                    "mac"=>"00:50:56:ae:90:ab"}
    sn = Bosh::AzureCloud::ManualNetwork.new("default", network_spec)

    expect(sn.private_ip).to eq("172.20.214.10")
  end
end
