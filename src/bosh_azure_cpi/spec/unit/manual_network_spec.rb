require "spec_helper"

describe Bosh::AzureCloud::ManualNetwork do
  let(:network_spec) {{}}

  context "when everything is fine" do
    let(:network_spec) {
      {
        "ip" => "fake-ip",
        "cloud_properties"=>{
          "virtual_network_name"=>"foo",
          "subnet_name"=>"bar"
        }
      }
    }

    it "should set the IP in manual networking" do
      sn = Bosh::AzureCloud::ManualNetwork.new("default", network_spec)

      expect(sn.private_ip).to eq("fake-ip")
    end
  end

  context "when missing some required properties" do
    context "missing cloud_properties" do
      let(:network_spec) {
        {
          "fake-key" => "fake-value"
        }
      }

      it "should raise an error" do
          expect {
            Bosh::AzureCloud::ManualNetwork.new("default", network_spec)
          }.to raise_error(/cloud_properties required for manual network/)
      end
    end

    context "missing virtual_network_name" do
      context "missing virtual_network_name" do
        let(:network_spec) {
          {
            "cloud_properties"=>{
              "subnet_name"=>"bar"
            }
          }
        }

        it "should raise an error" do
            expect {
              Bosh::AzureCloud::ManualNetwork.new("default", network_spec)
            }.to raise_error(/virtual_network_name required for manual network/)
        end
      end

      context "virtual_network_name is nil" do
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
              Bosh::AzureCloud::ManualNetwork.new("default", network_spec)
            }.to raise_error(/virtual_network_name required for manual network/)
        end
      end
    end

    context "missing subnet_name" do
      context "missing subnet_name" do
        let(:network_spec) {
          {
            "cloud_properties"=>{
              "virtual_network_name"=>"foo"
            }
          }
        }

        it "should raise an error" do
            expect {
              Bosh::AzureCloud::ManualNetwork.new("default", network_spec)
            }.to raise_error(/subnet_name required for manual network/)
        end
      end

      context "subnet_name is nil" do
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
              Bosh::AzureCloud::ManualNetwork.new("default", network_spec)
            }.to raise_error(/subnet_name required for manual network/)
        end
      end
    end
  end
end
