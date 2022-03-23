# frozen_string_literal: true

require 'spec_helper'
require 'monkey_patches/uri_monkey_patch'
describe Bosh::AzureCloud::URIMonkeyPatch do
  describe '.apply_patch' do
    context 'when URI does not have an escape method' do
      before { URI.instance_eval { undef :escape } }

      it 'should add the escape function' do
        expect { URI.method(:escape) }.to raise_error(NameError)
        expect { Bosh::AzureCloud::URIMonkeyPatch.apply_patch }.not_to raise_error
        expect { URI.method(:escape) }.not_to raise_error
      end

      context 'and azure-storage-table library is not 2.0.4' do
        let(:mismatch_version) { '2.0.5' }

        before do
          allow(::Azure::Storage::Table::Version).to receive(:to_s).and_return(mismatch_version)
        end

        it 'should raise an exception' do
          expect { Bosh::AzureCloud::URIMonkeyPatch.apply_patch }.to raise_error(Bosh::AzureCloud::URIMonkeyPatch::AZURE_VERSION_MISMATCH_WARNING)
        end
      end
    end

    context 'when URI has an escape method' do
      before do
        allow(::URI).to receive(:method_defined?).with(:escape).and_return(true)
      end

      it 'should not modify the current escape method' do
        allow(URI).to receive(:class_eval)

        expect { Bosh::AzureCloud::URIMonkeyPatch.apply_patch }.not_to raise_error
        expect(URI).not_to receive(:class_eval)
      end
    end
  end
end
