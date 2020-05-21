# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#initialize' do
    let(:cpi_lock_dir) { Bosh::AzureCloud::Helpers::CPI_LOCK_DIR }

    context 'when there is no proper network access to Azure' do
      before do
        allow(Bosh::AzureCloud::TableManager).to receive(:new).and_raise(Net::OpenTimeout, 'execution expired')
      end

      it 'raises an exception with a user friendly message' do
        expect(FileUtils).to receive(:mkdir_p).with(CPI_LOCK_DIR).and_call_original
        expect do
          cloud.has_vm?("fake-vm-cid")
        end.to raise_error(Bosh::Clouds::CloudError, 'Please make sure the CPI has proper network access to Azure. #<Net::OpenTimeout: execution expired>')
      end
    end

    context 'api_version' do
      it 'defaults to api version 1' do
        expect(cloud.api_version).to eq(1)
      end

      it 'can be set' do
        expect(cloud_v2.api_version).to eq(2)
      end
    end

    context 'stemcell api version in context' do
      it 'defaults to stemcell api version 1' do
        expect(cloud.stemcell_api_version).to eq(1)
      end

      it 'reads from context' do
        expect(cloud_sc_v2.stemcell_api_version).to eq(2)
      end
    end
  end
end
