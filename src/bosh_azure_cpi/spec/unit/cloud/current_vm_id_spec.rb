# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#current_vm_id' do
    it 'should raise a NotSupported error' do
      expect do
        cloud.current_vm_id
      end.to raise_error(Bosh::Clouds::NotSupported)
    end
  end
end
