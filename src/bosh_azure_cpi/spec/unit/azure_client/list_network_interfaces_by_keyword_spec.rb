# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  describe '#list_network_interfaces_by_keyword' do
    let(:network_interfaces_url) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces?api-version=#{api_version_network}" }
    let(:instance_id) { 'fake-instance-id' }

    context 'when network interfaces are not found' do
      let(:result) { { 'value' => [] }.to_json }
      it 'should return an empty array of network interfaces' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, network_interfaces_url).to_return(
          status: 200,
          body: result,
          headers: {
          }
        )
        expect(
          azure_client.list_network_interfaces_by_keyword(resource_group, instance_id)
        ).to eq([])
      end
    end

    context 'when network interfaces are found and some of them have the keyword in the name' do
      # The first NIC's response body includes networkSecurityGroup, publicIPAddress, loadBalancerBackendAddressPools and applicationGatewayBackendAddressPools
      let(:response_body) do
        {
          'value' => [
            {
              'name' => "#{instance_id}-0",
              'id' => 'a',
              'location' => 'b',
              'tags' => {},
              'properties' => {
                'provisioningState' => 'c',
                'ipConfigurations' => [
                  {
                    'id' => 'd0',
                    'properties' => {
                      'privateIPAddress' => 'e0',
                      'privateIPAllocationMethod' => 'f0',
                      'publicIPAddress' => {
                        'id' => 'j'
                      },
                      'loadBalancerBackendAddressPools' => [
                        {
                          'id' => 'k'
                        }
                      ],
                      'applicationGatewayBackendAddressPools' => [
                        {
                          'id' => 'l'
                        }
                      ],
                      'applicationSecurityGroups' => [
                        {
                          'id' => 'asg-id-1'
                        }
                      ]
                    }
                  }
                ],
                'dnsSettings' => {
                  'dnsServers' => %w[
                    g
                    h
                  ]
                },
                'networkSecurityGroup' => {
                  'id' => 'i'
                }
              }
            },
            {
              'name' => "#{instance_id}-1",
              'id' => 'a',
              'location' => 'b',
              'tags' => {},
              'properties' => {
                'provisioningState' => 'c',
                'ipConfigurations' => [
                  {
                    'id' => 'd1',
                    'properties' => {
                      'privateIPAddress' => 'e1',
                      'privateIPAllocationMethod' => 'f1'
                    }
                  }
                ],
                'dnsSettings' => {
                  'dnsServers' => %w[
                    g
                    h
                  ]
                }
              }
            },
            {
              'name' => 'the-name-witout-keyword',
              'id' => 'a',
              'location' => 'b',
              'tags' => {},
              'properties' => {
                'provisioningState' => 'c',
                'ipConfigurations' => [
                  {
                    'id' => 'd2',
                    'properties' => {
                      'privateIPAddress' => 'e2',
                      'privateIPAllocationMethod' => 'f2'
                    }
                  }
                ],
                'dnsSettings' => {
                  'dnsServers' => %w[
                    g
                    h
                  ]
                }
              }
            }
          ]
        }.to_json
      end
      let(:network_interface_0) do
        {
          id: 'a',
          name: "#{instance_id}-0",
          location: 'b',
          tags: {},
          provisioning_state: 'c',
          dns_settings: %w[g h],
          ip_configuration_id: 'd0',
          private_ip: 'e0',
          private_ip_allocation_method: 'f0',
          network_security_group: { id: 'i' },
          public_ip: { id: 'j' },
          load_balancer: { id: 'k' },
          application_gateway: { id: 'l' },
          application_security_groups: [{ id: 'asg-id-1' }]
        }
      end
      let(:network_interface_1) do
        {
          id: 'a',
          name: "#{instance_id}-1",
          location: 'b',
          tags: {},
          provisioning_state: 'c',
          dns_settings: %w[g h],
          ip_configuration_id: 'd1',
          private_ip: 'e1',
          private_ip_allocation_method: 'f1'
        }
      end
      it 'should return network interfaces' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, network_interfaces_url).to_return(
          status: 200,
          body: response_body,
          headers: {
          }
        )

        expect(
          azure_client.list_network_interfaces_by_keyword(resource_group, instance_id)
        ).to eq([network_interface_0, network_interface_1])
      end
    end
  end
end
