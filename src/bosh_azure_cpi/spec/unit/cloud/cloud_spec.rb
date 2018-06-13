# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#initialize' do
    let(:cpi_lock_dir) { Bosh::AzureCloud::Helpers::CPI_LOCK_DIR }
    let(:cpi_lock_delete) { Bosh::AzureCloud::Helpers::CPI_LOCK_DELETE }

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
        Dir.mkdir(cpi_lock_dir) unless Dir.exist?(cpi_lock_dir)
      end

      after do
        Dir.delete(cpi_lock_dir) if Dir.exist?(cpi_lock_dir)
      end

      context "when CPI doesn't need to cleanup locks" do
        before do
          allow(File).to receive(:exist?).with(cpi_lock_delete).and_return(false)
        end

        it 'should not create the cpi lock dir and cleanup the locks' do
          expect(Dir).not_to receive(:mkdir)
          expect(Dir).not_to receive(:glob)
          expect do
            cloud
          end.not_to raise_error
        end
      end

      context 'when CPI needs to cleanup locks' do
        before do
          allow(File).to receive(:exist?).with(cpi_lock_delete).and_return(true)
        end

        it 'should not create the cpi lock dir, but should cleanup the locks and the deleting mark' do
          expect(Dir).not_to receive(:mkdir)
          expect(Dir).to receive(:glob)
            .and_yield("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-1")
            .and_yield("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-2")
          expect(File).to receive(:delete).with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-1").once
          expect(File).to receive(:delete).with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-2").once
          expect(File).to receive(:delete).with(cpi_lock_delete).once
          expect do
            cloud
          end.not_to raise_error
        end

        context 'when the locks have been deleted by other processes' do
          it 'should not create the cpi lock dir, but should cleanup the locks and the deleting mark, and ignore the errors of non-existent locks' do
            expect(Dir).not_to receive(:mkdir)
            expect(Dir).to receive(:glob)
              .and_yield("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-1")
              .and_yield("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-2")
            expect(File).to receive(:delete).with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-1").once.and_raise(Errno::ENOENT)
            expect(File).to receive(:delete).with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_PREFIX}-fake-lock-2").once.and_raise(Errno::ENOENT)
            expect(File).to receive(:delete).with(cpi_lock_delete).and_raise(Errno::ENOENT)
            expect do
              cloud
            end.not_to raise_error
          end
        end
      end
    end

    context "when the lock dir doesn't exist" do
      before do
        Dir.delete(cpi_lock_dir) if Dir.exist?(cpi_lock_dir)
      end

      it 'should create the cpi lock dir' do
        expect(Dir).to receive(:mkdir).with(cpi_lock_dir)
        expect do
          cloud
        end.not_to raise_error
      end

      context 'when the lock dir is created by other processes' do
        it 'should create the lock dir and ignore the error of exising directory, but not clean the locks' do
          expect(Dir).to receive(:mkdir).with(cpi_lock_dir).and_return(Errno::EEXIST)
          expect(Dir).not_to receive(:glob)
          expect do
            cloud
          end.not_to raise_error
        end
      end
    end
  end
end
