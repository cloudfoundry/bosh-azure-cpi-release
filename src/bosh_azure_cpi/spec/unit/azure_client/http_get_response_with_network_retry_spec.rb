# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'
  describe '#http_get_response_with_network_retry' do
    let(:http_handler) { double('http') }
    let(:request) { double('request') }
    let(:response) { double('response') }

    context 'when retrable network errors happen' do
      [
        Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError,
        OpenSSL::SSL::SSLError.new(ERROR_MSG_OPENSSL_RESET), OpenSSL::X509::StoreError.new(ERROR_MSG_OPENSSL_RESET),
        StandardError.new('Hostname not known'), StandardError.new('Connection refused - connect(2) for \"xx.xxx.xxx.xx\" port 443')
      ].each do |error|
        context "when #{error} is raised" do
          before do
            allow(http_handler).to receive(:request).with(request).and_raise(error)
          end

          it "should retry for #{AZURE_MAX_RETRY_COUNT} times and fail finally" do
            expect(azure_client).to receive(:sleep).with(5).exactly(AZURE_MAX_RETRY_COUNT).times
            expect do
              azure_client.send(:http_get_response_with_network_retry, http_handler, request)
            end.to raise_error(error)
          end
        end

        context "when #{error} is raised at the first time but returns 200 at the second time" do
          before do
            times_called = 0
            allow(http_handler).to receive(:request).with(request) do
              times_called += 1
              raise error if times_called == 1 # raise error 1 time

              response
            end
          end

          it 'should retry for 1 time and get response finally' do
            expect(azure_client).to receive(:sleep).with(5).once
            expect(
              azure_client.send(:http_get_response_with_network_retry, http_handler, request)
            ).to be(response)
          end
        end
      end
    end

    context 'when non-retrable network errors happen' do
      # OpenSSL::SSL::SSLError and OpenSSL::X509::StoreError without specified message ERROR_MSG_OPENSSL_RESET
      # Errors without 'Hostname not known' and 'Connection refused - connect(2) for \"xx.xxx.xxx.xx\" port 443'
      [
        OpenSSL::SSL::SSLError.new, OpenSSL::X509::StoreError.new, StandardError.new
      ].each do |error|
        context "when #{error} is raised" do
          before do
            allow(http_handler).to receive(:request).with(request).and_raise(error)
          end

          it 'should raise error without retry' do
            expect(azure_client).not_to receive(:sleep)
            expect do
              azure_client.send(:http_get_response_with_network_retry, http_handler, request)
            end.to raise_error(error)
          end
        end
      end
    end
  end
end
