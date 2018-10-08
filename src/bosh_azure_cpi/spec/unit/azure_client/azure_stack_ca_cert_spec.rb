# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_stack_domain) { 'fake-azure-stack-domain' }
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  describe '#azure_stack_ca_cert' do
    let(:azure_client) do
      Bosh::AzureCloud::AzureClient.new(
        mock_azure_config(
          mock_cloud_options['properties']['azure'].merge!(
            'environment' => 'AzureStack',
            'azure_stack' => {
              'domain'              => azure_stack_domain,
              'resource'            => 'fake-resource',
              'skip_ssl_validation' => false,
              'ca_cert'             => 'fake-ca-cert-content'
            }
          )
        ),
        logger
      )
    end
    let(:ca_file_path) { '/var/vcap/jobs/azure_cpi/config/azure_stack_ca_cert.pem' }

    context "when the uri doesn't contain the AzureStack domain" do
      let(:uri) { URI('https://fake-host') }

      it 'should not configure the ca file' do
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:ssl_version=).with(:TLSv1_2)
        expect(http).not_to receive(:ca_file=).with(ca_file_path)
        expect(http).to receive(:open_timeout=).with(60)
        azure_client.send(:http, uri)
      end
    end

    context 'when the uri contains the AzureStack domain' do
      let(:uri) { URI("https://#{azure_stack_domain}") }

      it 'should configure the ca file' do
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:ssl_version=).with(:TLSv1_2)
        expect(http).to receive(:ca_file=).with(ca_file_path)
        expect(http).to receive(:open_timeout=).with(60)
        azure_client.send(:http, uri)
      end
    end
  end
end
