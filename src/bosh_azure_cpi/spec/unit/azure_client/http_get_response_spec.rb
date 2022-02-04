# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }

  describe '#http_get_response' do
    let(:uri) { double('uri') }
    let(:request) { double('request') }
    let(:retry_after) { 5 }
    let(:azure_client) do
      Bosh::AzureCloud::AzureClient.new(
        mock_azure_config,
        logger
      )
    end
    let(:response) { double('response') }

    before do
      allow(azure_client).to receive(:merge_http_common_headers).and_return(request)
      allow(request).to receive(:method).and_return('GET')
      allow(request).to receive(:[]=)
      allow(request).to receive(:[]).and_return('fake-value')
      allow(azure_client).to receive(:http).with(uri)
      allow(azure_client).to receive(:http_get_response_with_network_retry).and_return(response)
      allow(response).to receive(:body).and_return('fake-response-body')
      allow(azure_client).to receive(:get_http_common_headers).and_return('fake-value')
      allow(azure_client).to receive(:filter_credential_in_logs).and_return(true)
    end

    context 'when the response status code is 200' do
      before do
        allow(response).to receive(:code).and_return(200)
      end

      it 'should return the response' do
        expect(azure_client).to receive(:get_token).with(false).and_return('first-token').once
        expect(
          azure_client.send(:http_get_response, uri, request, retry_after)
        ).to be(response)
      end
    end

    context 'when the response status code is HTTP_CODE_UNAUTHORIZED (401)' do
      context 'when the status code is 401 at the first time but 200 at the second time' do
        before do
          allow(response).to receive(:code).and_return(401, 200)
        end

        it 'should retry for 1 time and get response finally' do
          expect(azure_client).to receive(:get_token).with(false).and_return('first-token').once
          expect(azure_client).to receive(:get_token).with(true).and_return('second-token').once
          expect(
            azure_client.send(:http_get_response, uri, request, retry_after)
          ).to be(response)
        end
      end

      context 'when the status code is always 401' do
        before do
          allow(response).to receive(:code).and_return(401)
        end

        it 'should raise error' do
          expect(azure_client).to receive(:get_token).with(false).and_return('first-token').once
          expect(azure_client).to receive(:get_token).with(true).and_return('second-token').once
          expect do
            azure_client.send(:http_get_response, uri, request, retry_after)
          end.to raise_error(/http_get_response - Azure authentication failed: Token is invalid/)
        end
      end
    end

    context 'when the response status code is one of AZURE_GENERAL_RETRY_ERROR_CODES ([408, 429, 500, 502, 503, 504])' do
      let(:retry_after) { 10 }

      before do
        allow(response).to receive(:key?).with('Retry-After').and_return(true)
        allow(response).to receive(:[]).with('Retry-After').and_return(retry_after)
      end

      context 'when the status code is 408 for 2 times but 200 at the third time' do
        before do
          allow(response).to receive(:code).and_return(408, 408, 200)
        end

        it 'should retry for 2 times and get response finally' do
          expect(azure_client).to receive(:get_token).with(false).and_return('first-token').exactly(3).times
          expect(azure_client).to receive(:sleep).with(retry_after).twice
          expect(
            azure_client.send(:http_get_response, uri, request, retry_after)
          ).to be(response)
        end
      end

      context 'when the status code is always 408' do
        before do
          allow(response).to receive(:code).and_return(408)
        end

        it 'should raise error' do
          expect(azure_client).to receive(:get_token).with(false).and_return('first-token').exactly(AZURE_MAX_RETRY_COUNT).times
          expect(azure_client).to receive(:sleep).with(retry_after).exactly(AZURE_MAX_RETRY_COUNT - 1).times
          expect do
            azure_client.send(:http_get_response, uri, request, retry_after)
          end.to raise_error(/http_get_response - Failed to get http response after #{AZURE_MAX_RETRY_COUNT} times/)
        end
      end
    end
  end
end
