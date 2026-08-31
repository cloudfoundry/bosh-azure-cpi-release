# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:azure_config) { mock_azure_config }
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) { Bosh::AzureCloud::AzureClient.new(azure_config, logger) }

  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { 'fake-vm-name' }
  let(:tags) { { 'fake-key' => 'fake-value' } }

  let(:valid_access_token) { 'valid-access-token' }

  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#update_tags_of_virtual_machine' do
    let(:vm_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }

    context 'when the virtual machine is found' do
      context "when VM's information contains tags" do
        let(:exiting_tags) do
          {
            'tag-name-1' => 'tag-value-1',
            'tag-name-2' => 'tag-value-2'
          }
        end
        let(:exiting_vm) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => exiting_tags,
            'properties' => {
              'provisioningState' => 'fake-state'
            },
            'resources' => [
              {
                properties: {},
                id: 'fake-id',
                name: 'fake-name',
                type: 'fake-type',
                location: 'fake-location'
              }
            ]
          }.to_json
        end
        let(:updated_vm) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => tags.merge(exiting_tags),
            'properties' => {
              'provisioningState' => 'fake-state'
            }
          }
        end

        it 'should merge the custom tags with existing tags' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: exiting_vm,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: updated_vm).to_return(
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
            azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
          end.not_to raise_error
        end

        it 'retries the complete update when Azure rejects a concurrent write' do
          allow(logger).to receive(:warn)
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: exiting_vm,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: updated_vm).to_return(
            {
              status: 409,
              body: '{"error":{"code":"ConflictingConcurrentWriteNotAllowed"}}',
              headers: {}
            },
            {
              status: 200,
              body: '',
              headers: {
                'azure-asyncoperation' => operation_status_link
              }
            }
          )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{"status":"Succeeded"}',
            headers: {}
          )

          expect do
            azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
          end.not_to raise_error
          expect(a_request(:get, vm_uri)).to have_been_requested.times(2)
          expect(a_request(:put, vm_uri).with(body: updated_vm)).to have_been_requested.times(2)
          expect(a_request(:get, operation_status_link)).to have_been_requested.once
          expect(azure_client).to have_received(:sleep).with(5).twice
          expect(logger).to have_received(:warn).with('update_tags_of_virtual_machine - concurrent write conflict. Will retry after 5 seconds.').once
        end

        it 'stops retrying concurrent writes after the retry limit' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: exiting_vm,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: updated_vm).to_return(
            status: 409,
            body: '{"error":{"code":"ConflictingConcurrentWriteNotAllowed"}}',
            headers: {}
          )

          expect do
            azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
          end.to raise_error Bosh::AzureCloud::AzureConflictError
          expect(a_request(:get, vm_uri)).to have_been_requested.times(AZURE_MAX_RETRY_COUNT + 1)
          expect(a_request(:put, vm_uri).with(body: updated_vm)).to have_been_requested.times(AZURE_MAX_RETRY_COUNT + 1)
          expect(azure_client).to have_received(:sleep).with(5).exactly(AZURE_MAX_RETRY_COUNT).times
        end

        it 'does not retry other Azure conflict errors' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: exiting_vm,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: updated_vm).to_return(
            status: 409,
            body: '{"error":{"code":"AnotherConflict"}}',
            headers: {}
          )

          expect do
            azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
          end.to raise_error Bosh::AzureCloud::AzureConflictError
          expect(a_request(:put, vm_uri).with(body: updated_vm)).to have_been_requested.once
          expect(azure_client).not_to have_received(:sleep)
        end

        it 'does not retry conflicts with the concurrent-write phrase outside the error body' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: exiting_vm,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: updated_vm).to_return(
            status: 409,
            body: 'not JSON',
            headers: {
              'x-ms-request-id' => 'ConflictingConcurrentWriteNotAllowed'
            }
          )

          expect do
            azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
          end.to raise_error Bosh::AzureCloud::AzureConflictError
          expect(a_request(:put, vm_uri).with(body: updated_vm)).to have_been_requested.once
          expect(azure_client).not_to have_received(:sleep)
        end
      end

      context "when VM's information doesn't contain tags" do
        let(:updated_vm) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => tags,
            'properties' => {
              'provisioningState' => 'fake-state'
            }
          }
        end

        context "when VM's information does not contain 'resources'" do
          let(:exiting_vm) do
            {
              'id' => 'fake-id',
              'name' => 'fake-name',
              'location' => 'fake-location',
              'tags' => {},
              'properties' => {
                'provisioningState' => 'fake-state'
              }
            }.to_json
          end

          it 'should raise no error' do
            stub_request(:post, token_uri).to_return(
              status: 200,
              body: {
                'access_token' => valid_access_token,
                'expires_on' => expires_on
              }.to_json,
              headers: {}
            )
            stub_request(:get, vm_uri).to_return(
              status: 200,
              body: exiting_vm,
              headers: {}
            )
            stub_request(:put, vm_uri).with(body: updated_vm).to_return(
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
              azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
            end.not_to raise_error
          end
        end

        context "when VM's information contains 'resources'" do
          let(:exiting_vm) do
            {
              'id' => 'fake-id',
              'name' => 'fake-name',
              'location' => 'fake-location',
              'tags' => {},
              'properties' => {
                'provisioningState' => 'fake-state'
              },
              'resources' => [
                {
                  properties: {},
                  id: 'fake-id',
                  name: 'fake-name',
                  type: 'fake-type',
                  location: 'fake-location'
                }
              ]
            }.to_json
          end

          it 'should raise no error' do
            stub_request(:post, token_uri).to_return(
              status: 200,
              body: {
                'access_token' => valid_access_token,
                'expires_on' => expires_on
              }.to_json,
              headers: {}
            )
            stub_request(:get, vm_uri).to_return(
              status: 200,
              body: exiting_vm,
              headers: {}
            )
            stub_request(:put, vm_uri).with(body: updated_vm).to_return(
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
              azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
            end.not_to raise_error
          end
        end
      end
    end

    context 'when the virtual machine is not found' do
      it 'should raise an error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, vm_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        stub_request(:put, vm_uri).to_return(
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
          azure_client.update_tags_of_virtual_machine(resource_group, vm_name, tags)
        end.to raise_error(/update_tags_of_virtual_machine - cannot find the virtual machine by name/)
      end
    end
  end
end
