require "spec_helper"

describe Bosh::AzureCloud::Helpers do
  class HelpersTester
    include Bosh::AzureCloud::Helpers
  end

  helpers_tester = HelpersTester.new

  describe "#encode_metadata" do
    let(:metadata) do
      {
        "user-agent" => "bosh",
        "foo"        => 1,
        "bar"        => true
      }
    end

    it "should return an encoded metadata" do
      expect(helpers_tester.encode_metadata(metadata)).to include(
        "user-agent" => "bosh",
        "foo"        => "1",
        "bar"        => "true"
      )
    end
  end

  describe "#get_storage_account_name_from_instance_id" do
    context "when instance id is valid" do
      let(:storage_account_name) { "foostorageaccount" }
      let(:instance_id) { "#{storage_account_name}-12345688-1234" }

      it "should return the storage account name" do
        expect(
          helpers_tester.get_storage_account_name_from_instance_id(instance_id)
        ).to eq(storage_account_name)
      end
    end

    context "when instance id is invalid" do
      let(:storage_account_name) { "foostorageaccount" }
      let(:instance_id) { "#{storage_account_name}123456881234" }

      it "should raise an error" do
        expect {
          helpers_tester.get_storage_account_name_from_instance_id(instance_id)
        }.to raise_error /Invalid instance id/
      end
    end
  end

  describe "#validate_disk_caching" do
    context "when disk caching is invalid" do
      let(:caching) { "Invalid" }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_caching(caching)
        }.to raise_error /Unknown disk caching/
      end
    end
  end
end
