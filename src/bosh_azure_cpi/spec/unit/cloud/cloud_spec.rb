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
      context 'when not set' do
        let(:default_api_version) { 1 }
        let(:cloud) do
          # NOTE: We can't use `mock_cloud(nil)` here, because that method always explicitly passes both args to the underlying `initialize` method
          Bosh::AzureCloud::Cloud.new(mock_cloud_options['properties'])
        end

        it 'defaults to api version 1' do
          expect(cloud.api_version).to eq(default_api_version)
        end
      end

      context 'when explicitly set' do
        context 'to api version 1' do
          let(:api_version) { 1 }
          let(:cloud) { mock_cloud(nil, api_version) }

          it 'succeeds' do
            expect(cloud.api_version).to eq(api_version)
          end
        end

        context 'to api version 2' do
          let(:api_version) { 2 }

          it 'succeeds' do
            expect(cloud_v2.api_version).to eq(api_version)
          end
        end

        context 'to api version nil' do
          let(:api_version) { nil }

          it 'raises an exception' do
            expect do
              mock_cloud(nil, api_version)
            end.to raise_error(Bosh::Clouds::CloudError, "Invalid api_version '#{api_version}'")
          end
        end

        context 'to api version 3' do
          let(:api_version) { 3 }

          it 'raises an exception' do
            expect do
              mock_cloud(nil, api_version)
            end.to raise_error(Bosh::Clouds::CloudError, "Invalid api_version '#{api_version}'")
          end
        end
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
