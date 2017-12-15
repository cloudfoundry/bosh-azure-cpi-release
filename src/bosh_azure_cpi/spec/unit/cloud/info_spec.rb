require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#info' do
    describe 'stemcell_formats' do
      it 'supports azure-vhd' do
        expect(cloud.info['stemcell_formats']).to include('azure-vhd')
      end

      it 'supports azure-light' do
        expect(cloud.info['stemcell_formats']).to include('azure-light')
      end
    end
  end
end
