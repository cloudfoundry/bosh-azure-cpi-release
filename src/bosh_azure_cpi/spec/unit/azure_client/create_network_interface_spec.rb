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
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { 'valid-access-token' }

  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_network_interface' do
    let(:network_interface_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/#{nic_name}?api-version=#{api_version_network}" }

    let(:nic_name) { 'fake-nic-name' }
    let(:nsg_id) { 'fake-nsg-id' }
    let(:subnet) { { id: 'fake-subnet-id' } }
    let(:tags) { { 'foo' => 'bar' } }

    context 'when token is valid, create operation is accepted and completed' do
      context 'with private ip, public ip and dns servers' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            private_ip: '10.0.0.100',
            dns_servers: ['168.63.129.16'],
            public_ip: { id: 'fake-public-id' },
            network_security_group: { id: nsg_id },
            application_security_groups: [],
            load_balancers: nil,
            application_gateways: nil
          }
        end
        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: {
                id: nic_params[:network_security_group][:id]
              },
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nic_params[:private_ip],
                  privateIPAllocationMethod: 'Static',
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  subnet: {
                    id: subnet[:id]
                  }
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        it 'should create a network interface without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end
      end

      context 'without private ip, public ip and dns servers' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            network_security_group: { id: nsg_id },
            application_security_groups: [],
            load_balancers: nil,
            application_gateways: nil
          }
        end
        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: {
                id: nic_params[:network_security_group][:id]
              },
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nil,
                  privateIPAllocationMethod: 'Dynamic',
                  publicIPAddress: nil,
                  subnet: {
                    id: subnet[:id]
                  }
                }
              }],
              dnsSettings: {
                dnsServers: []
              }
            }
          }
        end

        it 'should create a network interface without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end
      end

      context 'without network security group' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            private_ip: '10.0.0.100',
            dns_servers: ['168.63.129.16'],
            public_ip: { id: 'fake-public-id' },
            network_security_group: nil,
            application_security_groups: [],
            load_balancers: nil,
            application_gateways: nil
          }
        end
        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: nil,
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nic_params[:private_ip],
                  privateIPAllocationMethod: 'Static',
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  subnet: {
                    id: subnet[:id]
                  }
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        it 'should create a network interface without network security group' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end
      end

      context 'with load balancer' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            private_ip: '10.0.0.100',
            dns_servers: ['168.63.129.16'],
            public_ip: { id: 'fake-public-id' },
            network_security_group: { id: nsg_id },
            application_security_groups: [],
            load_balancers: [{
              backend_address_pools: [
                {
                  id: 'fake-id'
                }
              ],
              frontend_ip_configurations: [
                {
                  inbound_nat_rules: [{}]
                }
              ]
            }],
            application_gateways: nil
          }
        end

        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: {
                id: nic_params[:network_security_group][:id]
              },
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nic_params[:private_ip],
                  privateIPAllocationMethod: 'Static',
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  subnet: {
                    id: subnet[:id]
                  },
                  loadBalancerBackendAddressPools: [
                    {
                      id: 'fake-id'
                    }
                  ],
                  loadBalancerInboundNatRules: [{}]
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        it 'should create a network interface without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end

        context 'with multiple backend pools' do
          # TODO: issue-644: multi-BEPool-LB: add unit tests for multi-pool LBs
          it 'should create a network interface without error'

          context 'when backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-LB: add unit tests for named-pool LBs
            it 'should use the specified backend_pool'
          end

          context 'when an invalid backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-LB: add unit tests for named-pool LBs
            it 'should raise an error'
          end
        end
      end

      context 'with multiple load balancers' do # rubocop:disable RSpec/RepeatedExampleGroupBody
        # TODO: issue-644: multi-LB: add unit tests for multi-LBs
        it 'should create a network interface without error'

        context 'with multiple backend pools' do
          # TODO: issue-644: multi-BEPool-LB: add unit tests for multi-pool LBs
          it 'should create a network interface without error'

          context 'when backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-LB: add unit tests for named-pool LBs
            it 'should use the specified backend_pool'
          end
        end
      end

      context 'with application security groups' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            private_ip: '10.0.0.100',
            dns_servers: ['168.63.129.16'],
            public_ip: { id: 'fake-public-id' },
            network_security_group: { id: nsg_id },
            application_security_groups: [{ id: 'fake-asg-id-1' }, { id: 'fake-asg-id-2' }],
            load_balancers: nil,
            application_gateways: nil
          }
        end
        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: {
                id: nic_params[:network_security_group][:id]
              },
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nic_params[:private_ip],
                  privateIPAllocationMethod: 'Static',
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  subnet: {
                    id: subnet[:id]
                  },
                  applicationSecurityGroups: [
                    {
                      id: 'fake-asg-id-1'
                    },
                    {
                      id: 'fake-asg-id-2'
                    }
                  ]
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        it 'should create a network interface without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end
      end

      # NOTE: issue-644: unit tests for single-AGW, single-pool
      context 'with application gateway' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            ipconfig_name: 'fake-ipconfig-name',
            subnet: { id: subnet[:id] },
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            private_ip: '10.0.0.100',
            dns_servers: ['168.63.129.16'],
            public_ip: { id: 'fake-public-id' },
            network_security_group: { id: nsg_id },
            application_security_groups: [],
            load_balancers: nil,
            application_gateways: [{
              backend_address_pools: [
                {
                  id: 'fake-id-2'
                }
              ]
            }]
          }
        end
        let(:request_body) do
          {
            name: nic_params[:name],
            location: nic_params[:location],
            tags: {},
            properties: {
              networkSecurityGroup: {
                id: nic_params[:network_security_group][:id]
              },
              enableIPForwarding: false,
              enableAcceleratedNetworking: false,
              ipConfigurations: [{
                name: nic_params[:ipconfig_name],
                properties: {
                  privateIPAddress: nic_params[:private_ip],
                  privateIPAllocationMethod: 'Static',
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  subnet: {
                    id: subnet[:id]
                  },
                  applicationGatewayBackendAddressPools: [
                    {
                      id: 'fake-id-2'
                    }
                  ]
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        it 'should create a network interface without error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end

        context 'with multiple backend pools' do
          # TODO: issue-644: multi-BEPool-AGW: add unit tests for multi-pool AGWs
          it 'should create a network interface without error'

          context 'when backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-AGW: add unit tests for named-pool AGWs
            it 'should use the specified backend_pool'
          end

          context 'when an invalid backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-AGW: add unit tests for named-pool AGWs
            it 'should raise an error'
          end
        end
      end

      context 'with multiple application gateways' do # rubocop:disable RSpec/RepeatedExampleGroupBody
        # TODO: issue-644: multi-AGW: add unit tests for multi-AGWs
        it 'should create a network interface without error'

        context 'with multiple backend pools' do
          # TODO: issue-644: multi-BEPool-AGW: add unit tests for multi-pool AGWs
          it 'should create a network interface without error'

          context 'when backend_pool_name is specified' do
            # TODO: issue-644: multi-BEPool-AGW: add unit tests for named-pool AGWs
            it 'should use the specified backend_pool'
          end
        end
      end
    end
  end
end
