# frozen_string_literal: true

require 'spec_helper'
describe Bosh::AzureCloud::Batching do
  before do
    FileUtils.rm_rf("#{CPI_BATCH_TASK_DIR}/*")
    allow(Bosh::AzureCloud::Batching.instance).to receive(:sleep)
  end
  describe '#execute' do
    let(:vmss_name) { 'fake_vmss_name' }
    let(:instance_type) { 'fake_instance_type' }
    let(:sample_request) do
      {
        grouping_key: vmss_name,
        params: instance_type
      }
    end
    context 'when everything ok' do
      it 'task should been executed succesfully' do
        executor = lambda do |_, _|
          return ['1']
        end
        expect do
          result = Bosh::AzureCloud::Batching.instance.execute(sample_request, executor)
          expect(result).not_to eq(nil)
        end.not_to raise_error
      end
    end
    context 'when multiple requests come' do
      it 'task should been executed sucessfully' do
        executor = lambda do |_, _count|
          return %w[1 2]
        end
        task1 = Concurrent::Future.execute do
          Bosh::AzureCloud::Batching.instance.execute(sample_request, executor)
        end

        task2 = Concurrent::Future.execute do
          Bosh::AzureCloud::Batching.instance.execute(sample_request, executor)
        end

        expect do
          task1.wait!
          task2.wait!
        end.not_to raise_error
      end
    end
    context 'when rubbish in the task in file due to reboot or something' do
      let(:task_in_file_path) { "#{CPI_BATCH_TASK_DIR}/#{vmss_name}.tfin" }
      it 'should skip for the broken one' do
        FileUtils.mkdir_p(CPI_BATCH_TASK_DIR)
        File.open(task_in_file_path, 'a+') do |f|
          f.write('{"wrongjsonformat":')
          f.write("\n")
        end
        executor = lambda do |_, _|
          return ['1']
        end
        expect do
          result = Bosh::AzureCloud::Batching.instance.execute(sample_request, executor)
          expect(result).not_to eq(nil)
        end.not_to raise_error
      end
    end
  end
end
