# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::CPILogger do
  context '#set_request_id' do
    let(:message) { 'fake-message' }
    let(:request_id) { 'fake-req-id' }
    let(:log_file) { '/tmp/cpi-fake-logger.log' }
    let(:logger) { Bosh::AzureCloud::CPILogger.get_logger(log_file) }

    before do
      Bosh::AzureCloud::CPILogger.set_request_id(request_id)
    end

    after do
      File.delete(log_file)
    end

    it 'the logger should contain the request id, pid, tid, message' do
      logger.debug(message)
      content = File.readlines(log_file)[0]
      expect(content).to include('DEBUG', request_id, message, Process.pid.to_s, Thread.current.object_id.to_s)
    end
  end
end
