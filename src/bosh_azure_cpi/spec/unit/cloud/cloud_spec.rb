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
        expect(FileUtils).to receive(:mkdir_p).with(CPI_BATCH_TASK_DIR).and_call_original
        expect do
          cloud
        end.to raise_error(Bosh::Clouds::CloudError, 'Please make sure the CPI has proper network access to Azure. #<Net::OpenTimeout: execution expired>')
      end
    end
  end
end
