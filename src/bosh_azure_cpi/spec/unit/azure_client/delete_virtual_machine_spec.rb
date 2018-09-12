# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:vm_name) { 'fake-vm-name' }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#delete_virtual_machine' do
    let(:vm_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }

    context 'when token is valid' do
      before do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
      end

      it 'should raise AzureNotFoundError if delete opration returns 404' do
        stub_request(:delete, vm_uri).to_return(
          status: 404,
          body: '',
          headers: {
          }
        )

        expect do
          azure_client.delete_virtual_machine(resource_group, vm_name)
        end.to raise_error Bosh::AzureCloud::AzureNotFoundError
      end

      it 'should raise no error if delete opration returns 200' do
        stub_request(:delete, vm_uri).to_return(
          status: 200,
          body: '',
          headers: {
          }
        )

        expect do
          azure_client.delete_virtual_machine(resource_group, vm_name)
        end.not_to raise_error
      end

      it 'should raise no error if delete opration returns 204' do
        stub_request(:delete, vm_uri).to_return(
          status: 204,
          body: '',
          headers: {
          }
        )

        expect do
          azure_client.delete_virtual_machine(resource_group, vm_name)
        end.not_to raise_error
      end

      context 'when delete operation needs to check (returns 202)' do
        it 'should raise no error if operation status is Succeeded' do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
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
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.not_to raise_error
        end

        it 'should not loop forever or raise an error if operation status is InProgress at first and Succeeded finally' do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
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
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.not_to raise_error
        end

        it "should retry and succeed if operation status is Failed with 'Retry-After' in the header at first and Succeeded finally" do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
            headers: {
              'azure-asyncoperation' => operation_status_link
            }
          )
          stub_request(:get, operation_status_link).to_return(
            {
              status: 200,
              body: '{"status":"Failed"}',
              headers: { 'Retry-After' => '1' }
            },
            status: 200,
            body: '{"status":"Succeeded"}',
            headers: {}
          )

          expect(azure_client).to receive(:sleep).with(1)
          expect(azure_client).to receive(:sleep).with(5).twice
          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.not_to raise_error
        end

        it "should not retry and raise an error if operation status is Failed without 'Retry-After' in the header" do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
            headers: {
              'azure-asyncoperation' => operation_status_link
            }
          )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{"status":"Failed"}',
            headers: {}
          )

          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error { |error| expect(error.status).to eq('Failed') }
        end

        it 'should raise an error if the body of the asynchronous response is empty' do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
            headers: {
              'azure-asyncoperation' => operation_status_link
            }
          )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            headers: {}
          )

          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error /The body of the asynchronous response is empty/
        end

        it "should raise an error if the body of the asynchronous response does not contain 'status'" do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
            headers: {
              'azure-asyncoperation' => operation_status_link
            }
          )
          stub_request(:get, operation_status_link).to_return(
            status: 200,
            body: '{}',
            headers: {}
          )

          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error /The body of the asynchronous response does not contain 'status'/
        end

        it 'should raise an error if check completion operation is not accepeted' do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
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
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error /check_completion - http code: 404/
        end

        it 'should raise an error if create peration failed' do
          stub_request(:delete, vm_uri).to_return(
            status: 202,
            body: '',
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
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error { |error| expect(error.status).to eq('Cancelled') }
        end
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
          stub_request(:delete, vm_uri).to_return(
            {
              status: 401,
              body: 'The token expired'
            },
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
        end

        it 'should not raise an error' do
          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
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
          stub_request(:delete, vm_uri).to_return(
            status: 401,
            body: '',
            headers: {}
          )

          expect do
            azure_client.delete_virtual_machine(resource_group, vm_name)
          end.to raise_error /Azure authentication failed: Token is invalid./
        end
      end
    end
  end
end
