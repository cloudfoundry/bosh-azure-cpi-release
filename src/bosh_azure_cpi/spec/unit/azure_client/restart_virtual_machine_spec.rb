# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      logger
    )
  end
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

  describe '#restart_virtual_machine' do
    let(:vm_restart_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}/restart?api-version=#{api_version_compute}" }

    context 'when token is valid, restart operation is accepted and completed' do
      it 'should raise no error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 202,
          body: '{}',
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
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.not_to raise_error
      end

      it 'should not loop forever or raise an error if restart operation is InProgress at first and Succeeded finally' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        stub_request(:get, operation_status_link).to_return(
          {
            status: 200,
            body: '{"status":"InProgress"}',
            headers: {}
          },
          status: 200,
          body: '{"status":"Succeeded"}',
          headers: {}
        )

        expect do
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.not_to raise_error
      end
    end

    context 'when token is valid but the VM cannot be found' do
      it 'should raise AzureNotFoundError' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect do
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.to raise_error Bosh::AzureCloud::AzureNotFoundError
      end
    end

    context 'when token is valid, restart operation is accepted and not completed' do
      it 'should raise an error if check completion operation is not acceptted' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        stub_request(:get, operation_status_link).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect do
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.to raise_error /check_completion - http code: 404/
      end

      it 'should raise error when internal error happens' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        stub_request(:get, operation_status_link).to_return(
          status: 200,
          body: '{"status":"Failed"}',
          headers: {
            'Retry-After' => '1'
          }
        )
        expect do
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.to raise_error /check_completion - http code: 200/
      end

      it 'should raise an error if restart operation failed' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vm_restart_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        stub_request(:get, operation_status_link).to_return(
          status: 200,
          body: '{"status":"Cancelled"}',
          headers: {}
        )

        expect do
          azure_client.restart_virtual_machine(resource_group, vm_name)
        end.to raise_error { |error| expect(error.status).to eq('Cancelled') }
      end
    end

    context 'when token expired' do
      context 'when authentication retry succeeds' do
        before do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:post, vm_restart_uri).to_return(
            {
              status: 401,
              body: 'The token expired'
            },
            status: 202,
            body: '{}',
            headers: {
              'azure-asyncoperation' => operation_status_link
            }
          )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{"status":"Succeeded"}',
            headers: {}
          )
        end

        it 'should not raise an error' do
          expect do
            azure_client.restart_virtual_machine(resource_group, vm_name)
          end.not_to raise_error
        end
      end

      context 'when authentication retry fails' do
        it 'should raise an error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:post, vm_restart_uri).to_return(
            status: 401,
            body: '',
            headers: {}
          )

          expect do
            azure_client.restart_virtual_machine(resource_group, vm_name)
          end.to raise_error /Azure authentication failed: Token is invalid./
        end
      end
    end
  end
end
