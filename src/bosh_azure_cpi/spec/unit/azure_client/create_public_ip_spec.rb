# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:public_ip_name) { 'fake-public-ip-name' }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_public_ip' do
    let(:public_ip_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/publicIPAddresses/#{public_ip_name}?api-version=#{api_version_network}" }

    let(:location) { 'fake-location' }

    context 'when token is valid, create operation is accepted and completed' do
      context 'when creating static public ip' do
        let(:public_ip_params) do
          {
            name: public_ip_name,
            location: location,
            idle_timeout_in_minutes: 4,
            is_static: true
          }
        end
        let(:fake_public_ip_request_body) do
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Static'
            }
          }
        end

        it 'should create a public ip without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
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
            azure_client.create_public_ip(resource_group, public_ip_params)
          end.not_to raise_error
        end
      end

      context 'when creating dynamic public ip' do
        let(:public_ip_params) do
          {
            name: public_ip_name,
            location: location,
            idle_timeout_in_minutes: 4,
            is_static: false
          }
        end
        let(:fake_public_ip_request_body) do
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Dynamic'
            }
          }
        end

        it 'should create a public ip without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
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
            azure_client.create_public_ip(resource_group, public_ip_params)
          end.not_to raise_error
        end
      end

      context 'when creating public ip in a zone' do
        let(:public_ip_params) do
          {
            name: public_ip_name,
            location: location,
            idle_timeout_in_minutes: 4,
            is_static: false,
            zone: 'fake-zone'
          }
        end
        let(:fake_public_ip_request_body) do
          {
            'name' => public_ip_name,
            'location' => location,
            'properties' => {
              'idleTimeoutInMinutes' => 4,
              'publicIPAllocationMethod' => 'Dynamic'
            },
            'zones' => ['fake-zone']
          }
        end

        it 'should create a public ip without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, public_ip_uri).with(body: fake_public_ip_request_body).to_return(
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
            azure_client.create_public_ip(resource_group, public_ip_params)
          end.not_to raise_error
        end
      end
    end
  end
end
