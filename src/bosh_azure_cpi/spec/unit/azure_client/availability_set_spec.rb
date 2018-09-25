# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:avset_name) { 'fake-avset-name' }
  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_availability_set' do
    let(:avset_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/#{avset_name}?api-version=#{api_version_compute}" }

    let(:avset_params) do
      {
        name: avset_name,
        location: 'fake-location',
        tags: { 'foo' => 'bar' },
        platform_update_domain_count: 5,
        platform_fault_domain_count: 2
      }
    end

    let(:request_body) do
      {
        name: avset_name,
        location: 'fake-location',
        type: 'Microsoft.Compute/availabilitySets',
        tags: {
          foo: 'bar'
        },
        properties: {
          platformUpdateDomainCount: 5,
          platformFaultDomainCount: 2
        }
      }
    end

    context 'When managed is null' do
      it 'should raise no error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client.create_availability_set(resource_group, avset_params)
        end.not_to raise_error
      end
    end

    context 'When managed is false' do
      before do
        avset_params[:managed] = false
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
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client.create_availability_set(resource_group, avset_params)
        end.not_to raise_error
      end
    end

    context 'When managed is true' do
      before do
        avset_params[:managed] = true
        request_body[:sku] = {
          name: 'Aligned'
        }
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
        stub_request(:put, avset_uri).with(body: request_body).to_return(
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
          azure_client.create_availability_set(resource_group, avset_params)
        end.not_to raise_error
      end
    end
  end

  describe '#get_availability_set_by_name' do
    let(:avset_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/#{avset_name}?api-version=#{api_version_compute}" }

    let(:response_body) do
      {
        id: 'a',
        name: avset_name,
        location: 'c',
        tags: {
          foo: 'bar'
        },
        sku: {
          name: 'Aligned'
        },
        properties: {
          provisioningState: 'd',
          platformUpdateDomainCount: 5,
          platformFaultDomainCount: 2
        }
      }
    end
    let(:avset) do
      {
        id: 'a',
        name: avset_name,
        location: 'c',
        tags: {
          'foo' => 'bar'
        },
        provisioning_state: 'd',
        platform_update_domain_count: 5,
        platform_fault_domain_count: 2,
        managed: true,
        virtual_machines: []
      }
    end

    context 'when there are no machines in the availibility set' do
      it 'should raise no error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, avset_uri).to_return(
          status: 200,
          body: response_body.to_json,
          headers: {}
        )

        expect(
          azure_client.get_availability_set_by_name(resource_group, avset_name)
        ).to eq(avset)
      end
    end

    context 'when there are machines in the availibility set' do
      before do
        response_body[:properties][:virtualMachines] = [
          {
            id: 'vm-id-1'
          },
          {
            id: 'vm-id-2'
          }
        ]
        avset[:virtual_machines] = response_body[:properties][:virtualMachines]
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
        stub_request(:get, avset_uri).to_return(
          status: 200,
          body: response_body.to_json,
          headers: {}
        )

        expect(
          azure_client.get_availability_set_by_name(resource_group, avset_name)
        ).to eq(avset)
      end
    end

    context 'when the response body of availibility set contains the property sku, and the sku name is Aligned' do
      it 'should raise no error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, avset_uri).to_return(
          status: 200,
          body: response_body.to_json,
          headers: {}
        )

        expect(
          azure_client.get_availability_set_by_name(resource_group, avset_name)
        ).to eq(avset)
      end
    end

    context 'when the response body of availibility set contains the property sku, and the sku name is Classic' do
      before do
        response_body[:sku][:name] = 'Classic'
        avset[:managed] = false
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
        stub_request(:get, avset_uri).to_return(
          status: 200,
          body: response_body.to_json,
          headers: {}
        )

        expect(
          azure_client.get_availability_set_by_name(resource_group, avset_name)
        ).to eq(avset)
      end
    end

    context 'when the response body of availibility set does not contain the property sku' do
      before do
        response_body.delete(:sku)
        avset[:managed] = false
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
        stub_request(:get, avset_uri).to_return(
          status: 200,
          body: response_body.to_json,
          headers: {}
        )

        expect(
          azure_client.get_availability_set_by_name(resource_group, avset_name)
        ).to eq(avset)
      end
    end
  end

  describe '#delete_availability_set' do
    let(:avset_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/availabilitySets/#{avset_name}?api-version=#{api_version_compute}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete the availability set without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, avset_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client.delete_availability_set(resource_group, avset_name)
        end.not_to raise_error
      end
    end
  end
end
