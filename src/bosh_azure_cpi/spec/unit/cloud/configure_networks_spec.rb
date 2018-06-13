# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#configure_networks' do
    let(:instance_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:networks) { 'networks' }

    it 'should raise a NotSupported error' do
      expect do
        cloud.configure_networks(instance_id, networks)
      end.to raise_error {
        Bosh::Clouds::NotSupported
      }
    end
  end
end
