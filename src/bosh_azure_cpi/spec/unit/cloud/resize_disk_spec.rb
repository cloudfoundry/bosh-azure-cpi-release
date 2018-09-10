# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#resize_disk' do
    let(:vm_cid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:new_size) { double('size') }

    it 'should raise a NotSupported error' do
      expect do
        cloud.resize_disk(vm_cid, new_size)
      end.to raise_error(Bosh::Clouds::NotSupported)
    end
  end
end
