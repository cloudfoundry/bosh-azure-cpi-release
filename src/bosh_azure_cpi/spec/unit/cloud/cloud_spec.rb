require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#initialize' do
    context 'when there is no proper network access to Azure' do
      let(:storage_account) {
        {
          :id => "foo",
          :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
          :location => "bar",
          :provisioning_state => "bar",
          :account_type => "foo",
          :primary_endpoints => "bar"
        }
      }
      before do
        allow(client2).to receive(:get_storage_account_by_name).and_return(storage_account)
        allow(Bosh::AzureCloud::TableManager).to receive(:new).and_raise(Net::OpenTimeout, 'execution expired')
      end

      it 'raises an exception with a user friendly message' do
        expect { cloud }.to raise_error(Bosh::Clouds::CloudError, 'Please make sure the CPI has proper network access to Azure. #<Net::OpenTimeout: execution expired>')
      end
    end
  end
end
