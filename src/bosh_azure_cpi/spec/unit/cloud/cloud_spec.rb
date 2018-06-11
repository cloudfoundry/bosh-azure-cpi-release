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
        expect do
          cloud
        end.to raise_error(Bosh::Clouds::CloudError, 'Please make sure the CPI has proper network access to Azure. #<Net::OpenTimeout: execution expired>')
      end
    end

    context 'when the lock dir exists' do
      before do
        allow(Dir).to receive(:exist?)
          .with(cpi_lock_dir)
          .and_return(true)
      end

      it 'should not create the cpi lock dir' do
        expect(Dir).not_to receive(:mkdir)
        expect do
          cloud
        end.not_to raise_error
      end
    end

    context "when the lock dir doesn't exist" do
      before do
        allow(Dir).to receive(:exist?)
          .with(cpi_lock_dir)
          .and_return(false)
      end

      it 'should create the cpi lock dir' do
        expect(Dir).to receive(:mkdir).with(cpi_lock_dir)
        expect do
          cloud
        end.not_to raise_error
      end

      context 'when the lock dir is created by other processes' do
        it 'should create the lock dir and ignore the error of exising directory' do
          expect(Dir).to receive(:mkdir).with(cpi_lock_dir).and_return(Errno::EEXIST)
          expect do
            cloud
          end.not_to raise_error
        end
      end
    end
  end
end
