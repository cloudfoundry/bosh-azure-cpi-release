# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#set_disk_metadata' do
    let(:disk_cid) { 'fake-disk-cid' }
    let(:metadata) { {} }

    it 'should raise a NotSupported error' do
      expect do
        cloud.set_disk_metadata(disk_cid, metadata)
      end.to raise_error {
        Bosh::Clouds::NotSupported
      }
    end
  end
end
