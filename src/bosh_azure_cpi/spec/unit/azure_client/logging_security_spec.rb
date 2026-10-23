# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AzureClient do
  [false, true].each do |debug_mode|
    context "when debug_mode is #{debug_mode}" do
      let(:azure_client) do
        Bosh::AzureCloud::AzureClient.new(mock_azure_config_merge('debug_mode' => debug_mode), Logger.new(StringIO.new))
      end

      it 'keeps credential fields redacted in application diagnostics' do
        body = {
          'client_assertion' => 'fixture-jwt',
          'client_secret' => 'fixture-secret',
          'access_token' => 'fixture-token',
          'properties' => { 'adminPassword' => 'fixture-password' }
        }
        request = azure_client.send(:redact_credentials_in_request_body, body)
        response = azure_client.send(:redact_credentials_in_response_body, body.to_json)
        [request, response].each do |logged|
          expect(logged).not_to include('fixture-')
          expect(JSON.parse(logged)['client_assertion']).to eq('<redacted>')
        end
      end

      it 'never enables a raw Net::HTTP debug writer' do
        transport = azure_client.send(:http, URI('https://example.invalid'))
        expect(transport.instance_variable_get(:@debug_output)).to be_nil
      end

      it 'suppresses storage-key response contents independently of debug verbosity' do
        uri = URI('https://management.azure.com/storageAccount/listKeys?api-version=fixture')
        expect(azure_client.send(:filter_credential_in_logs, uri)).to be(true)
      end
    end
  end
end
