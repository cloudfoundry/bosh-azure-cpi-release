# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:nic_name) { 'fake-nic-name' }

  describe '#delete_network_interface' do
    let(:network_interface_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/#{nic_name}?api-version=#{api_version_network}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete a network interface without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, network_interface_uri).to_return(
          status: 200,
          body: '',
          headers: {
          }
        )

        expect do
          azure_client.delete_network_interface(resource_group, nic_name)
        end.not_to raise_error
      end
    end
  end
end
