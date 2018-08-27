# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { 'fake-vm-name' }
  let(:valid_access_token) { 'valid-access-token' }

  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_virtual_machine' do # Use function create_virtual_machine to validate user agent
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}&validating=true" }

    let(:vm_params) do
      {
        name: vm_name,
        location: 'b',
        tags: { 'foo' => 'bar' },
        vm_size: 'c',
        ssh_username: 'd',
        ssh_cert_data: 'e',
        custom_data: 'f',
        image_uri: 'g',
        os_disk: {
          disk_name: 'h',
          disk_uri: 'i',
          disk_caching: 'j',
          disk_size: 'k'
        },
        ephemeral_disk: {
          disk_name: 'l',
          disk_uri: 'm',
          disk_caching: 'n',
          disk_size: 'o'
        },
        os_type: 'linux',
        managed: false
      }
    end

    let(:network_interfaces) do
      [
        { id: 'a' },
        { id: 'b' }
      ]
    end

    context 'parse http headers' do
      context 'when isv_tracking_guid is not provided' do
        let(:logger) { Bosh::Clouds::Config.logger }
        let(:azure_client) do
          Bosh::AzureCloud::AzureClient.new(
            mock_azure_config,
            logger
          )
        end
        let(:default_isv_tracking_guid) { 'pid-563bbbca-7944-4791-b9c6-8af0928114ac' }

        it 'should set the default guid in user agent' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, vm_uri)
            .with do |request|
              headers = request.headers
              expect(headers['Content-Type']).to eq('application/json')
              expect(headers['User-Agent']).to include("BOSH-AZURE-CPI/#{Bosh::AzureCloud::VERSION}")
              expect(headers['User-Agent']).to include(default_isv_tracking_guid)
            end
            .to_return(
              status: 200,
              body: '',
              headers: {
                'azure-asyncoperation' => operation_status_link
              }
            )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{"status":"Succeeded"}',
            headers: {}
          )

          expect do
            azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when isv_tracking_guid is provided' do
        let(:logger) { Bosh::Clouds::Config.logger }
        let(:isv_tracking_guid) { 'fake-isv-tracking-guid' }
        let(:azure_client) do
          Bosh::AzureCloud::AzureClient.new(
            mock_azure_config_merge('isv_tracking_guid' => isv_tracking_guid),
            logger
          )
        end

        it 'should set the guid in user agent' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, vm_uri)
            .with do |request|
              headers = request.headers
              expect(headers['Content-Type']).to eq('application/json')
              expect(headers['User-Agent']).to include("BOSH-AZURE-CPI/#{Bosh::AzureCloud::VERSION}")
              expect(headers['User-Agent']).to include("pid-#{isv_tracking_guid}")
            end
            .to_return(
              status: 200,
              body: '',
              headers: {
                'azure-asyncoperation' => operation_status_link
              }
            )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{"status":"Succeeded"}',
            headers: {}
          )

          expect do
            azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
          end.not_to raise_error
        end
      end
    end
  end
end
