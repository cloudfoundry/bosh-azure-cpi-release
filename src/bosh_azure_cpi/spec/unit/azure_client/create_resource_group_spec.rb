# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  describe '#create_resource_group' do
    let(:resource_group_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}?api-version=#{group_api_version}" }

    let(:location) { 'fake-location' }

    before do
      allow(azure_client).to receive(:sleep)
    end

    context 'when token is valid, create operation is accepted and completed' do
      context 'when it returns 200' do
        it 'should create a resource group without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, resource_group_uri).to_return(
            status: 200,
            body: '',
            headers: {
            }
          )

          expect do
            azure_client.create_resource_group(resource_group, location)
          end.not_to raise_error
        end
      end
    end

    context 'when it returns 201' do
      it 'should create a resource group without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, resource_group_uri).to_return(
          status: 201,
          body: '',
          headers: {
          }
        )

        expect do
          azure_client.create_resource_group(resource_group, location)
        end.not_to raise_error
      end
    end

    context 'when return 202, and then failed.' do
      it 'should raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, resource_group_uri).to_return(
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
          azure_client.create_resource_group(resource_group, location)
        end.to raise_error /check_completion - http code: 200/
      end
    end
  end
end
