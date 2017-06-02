require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe "#set_disk_metadata" do
    let(:disk_id) { "fake-disk-id" }
    let(:metadata) { {} }

    it 'should raise a NotSupported error' do
      expect {
        cloud.set_disk_metadata(disk_id, metadata)
      }.to raise_error {
        Bosh::Clouds::NotSupported
      }
    end
  end
end
