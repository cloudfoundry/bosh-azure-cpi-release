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
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: nic_params[:private_ip],
                  publicIPAddress: { id: nic_params[:public_ip][:id] }
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
                  privateIPAllocationMethod: 'Dynamic',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true
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
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: nic_params[:private_ip],
                  publicIPAddress: { id: nic_params[:public_ip][:id] }
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
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: nic_params[:private_ip],
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  loadBalancerBackendAddressPools: nic_params[:load_balancers].map { |lb| { id: lb[:backend_address_pools][0][:id] } },
                  loadBalancerInboundNatRules: nic_params[:load_balancers].flat_map { |lb| lb[:frontend_ip_configurations][0][:inbound_nat_rules] }.compact
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        before do
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
        end

        context 'with single load balancer' do
          context 'with single backend pool' do
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
                      name: 'fake-lb-pool-name',
                      id: 'fake-lb-pool-id'
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

            it 'should create a network interface without error' do
              expect do
                azure_client.create_network_interface(resource_group, nic_params)
              end.not_to raise_error
            end
          end

          context 'with multiple backend pools' do
            context 'when backend_pool_name is not specified' do
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
                        name: 'fake-lb-pool-name',
                        id: 'fake-lb-pool-id'
                      },
                      {
                        name: 'fake-lb-pool2-name',
                        id: 'fake-lb-pool2-id'
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

              it 'should use the default backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end

            context 'when backend_pool_name is specified' do
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
                  # NOTE: This data would normally be created by the `VMManager._get_load_balancers` method,
                  # which would remove all but the `vm_props`-configured pool from the list.
                  load_balancers: [{
                    backend_address_pools: [
                      {
                        name: 'fake-lb-pool2-name',
                        id: 'fake-lb-pool2-id'
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

              it 'should use the specified backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end
          end
        end

        context 'with multiple load balancers' do
          context 'with single backend pool' do
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
                load_balancers: [
                  {
                    backend_address_pools: [
                      {
                        name: 'fake-lb-pool-name',
                        id: 'fake-lb-pool-id'
                      }
                    ],
                    frontend_ip_configurations: [
                      {
                        inbound_nat_rules: [{}]
                      }
                    ]
                  },
                  {
                    backend_address_pools: [
                      {
                        name: 'fake-lb2-pool-1-name',
                        id: 'fake-lb2-pool-1-id'
                      }
                    ],
                    frontend_ip_configurations: [
                      {
                        inbound_nat_rules: [{}]
                      }
                    ]
                  }
                ],
                application_gateways: nil
              }
            end

            it 'should create a network interface without error' do
              expect do
                azure_client.create_network_interface(resource_group, nic_params)
              end.not_to raise_error
            end
          end

          context 'with multiple backend pools' do
            context 'when backend_pool_name is not specified' do
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
                  load_balancers: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-lb-pool-name',
                          id: 'fake-lb-pool-id'
                        },
                        {
                          name: 'fake-lb-pool2-name',
                          id: 'fake-lb-pool2-id'
                        }
                      ],
                      frontend_ip_configurations: [
                        {
                          inbound_nat_rules: [{}]
                        }
                      ]
                    },
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-lb2-pool-1-name',
                          id: 'fake-lb2-pool-1-id'
                        },
                        {
                          name: 'fake-lb2-pool-2-name',
                          id: 'fake-lb2-pool-2-id'
                        }
                      ],
                      frontend_ip_configurations: [
                        {
                          inbound_nat_rules: [{}]
                        }
                      ]
                    }
                  ],
                  application_gateways: nil
                }
              end

              it 'should use the default backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end

            context 'when backend_pool_name is specified' do
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
                  # NOTE: This data would normally be created by the `VMManager._get_load_balancers` method,
                  # which would remove all but the `vm_props`-configured pools from the list.
                  load_balancers: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-lb-pool2-name',
                          id: 'fake-lb-pool2-id'
                        }
                      ],
                      frontend_ip_configurations: [
                        {
                          inbound_nat_rules: [{}]
                        }
                      ]
                    },
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-lb2-pool-2-name',
                          id: 'fake-lb2-pool-2-id'
                        }
                      ],
                      frontend_ip_configurations: [
                        {
                          inbound_nat_rules: [{}]
                        }
                      ]
                    }
                  ],
                  application_gateways: nil
                }
              end

              it 'should use the specified backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end
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
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: nic_params[:private_ip],
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
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

      context 'with application gateway' do
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
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: nic_params[:private_ip],
                  publicIPAddress: { id: nic_params[:public_ip][:id] },
                  applicationGatewayBackendAddressPools: nic_params[:application_gateways].map { |agw| { id: agw[:backend_address_pools][0][:id] } }
                }
              }],
              dnsSettings: {
                dnsServers: ['168.63.129.16']
              }
            }
          }
        end

        before do
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
        end

        context 'with single application gateway' do
          context 'with single backend pool' do
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
                      name: 'fake-agw-pool-name',
                      id: 'fake-agw-pool-id'
                    }
                  ]
                }]
              }
            end

            it 'should create a network interface without error' do
              expect do
                azure_client.create_network_interface(resource_group, nic_params)
              end.not_to raise_error
            end
          end

          context 'with multiple backend pools' do
            context 'when backend_pool_name is not specified' do
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
                  application_gateways: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw-pool-name',
                          id: 'fake-agw-pool-id'
                        },
                        {
                          name: 'fake-agw-pool2-name',
                          id: 'fake-agw-pool2-id'
                        }
                      ]
                    }
                  ]
                }
              end

              it 'should use the default backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end

            context 'when backend_pool_name is specified' do
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
                  # NOTE: This data would normally be created by the `VMManager._get_application_gateways` method,
                  # which would remove all but the `vm_props`-configured pool from the list.
                  application_gateways: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw-pool2-name',
                          id: 'fake-agw-pool2-id'
                        }
                      ]
                    }
                  ]
                }
              end

              it 'should use the specified backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end
          end
        end

        context 'with multiple application gateways' do
          context 'with single backend pool' do
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
                application_gateways: [
                  {
                    backend_address_pools: [
                      {
                        name: 'fake-agw-pool-name',
                        id: 'fake-agw-pool-id'
                      }
                    ]
                  },
                  {
                    backend_address_pools: [
                      {
                        name: 'fake-agw2-pool-1-name',
                        id: 'fake-agw2-pool-1-id'
                      }
                    ]
                  }
                ]
              }
            end

            it 'should create a network interface without error' do
              expect do
                azure_client.create_network_interface(resource_group, nic_params)
              end.not_to raise_error
            end
          end

          context 'with multiple backend pools' do
            context 'when backend_pool_name is not specified' do
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
                  application_gateways: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw-pool-name',
                          id: 'fake-agw-pool-id'
                        },
                        {
                          name: 'fake-agw-pool2-name',
                          id: 'fake-agw-pool2-id'
                        }
                      ]
                    },
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw2-pool-1-name',
                          id: 'fake-agw2-pool-1-id'
                        },
                        {
                          name: 'fake-agw2-pool-2-name',
                          id: 'fake-agw2-pool-2-id'
                        }
                      ]
                    }
                  ]
                }
              end

              it 'should use the default backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end

            context 'when backend_pool_name is specified' do
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
                  # NOTE: This data would normally be created by the `VMManager._get_application_gateways` method,
                  # which would remove all but the `vm_props`-configured pools from the list.
                  application_gateways: [
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw-pool2-name',
                          id: 'fake-agw-pool2-id'
                        }
                      ]
                    },
                    {
                      backend_address_pools: [
                        {
                          name: 'fake-agw2-pool-2-name',
                          id: 'fake-agw2-pool-2-id'
                        }
                      ]
                    }
                  ]
                }
              end

              it 'should use the specified backend_pools' do
                expect do
                  azure_client.create_network_interface(resource_group, nic_params)
                end.not_to raise_error
              end
            end
          end
        end
      end
    end
  end


  describe '#create_network_interface (dual-stack)' do
    let(:nic_name) { 'fake-nic-name' }
    let(:nsg_id) { 'fake-nsg-id' }
    let(:subnet) { { id: 'fake-subnet-id' } }
    let(:network_interface_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Network/networkInterfaces/#{nic_name}?api-version=#{api_version_network}" }

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

    def stub_create_nic(expected_request_body)
      stub_request(:put, network_interface_uri)
        .with(body: expected_request_body.to_json)
        .to_return(
          status: 200,
          body: '',
          headers: { 'azure-asyncoperation' => operation_status_link }
        )
      stub_request(:get, operation_status_link).to_return(
        status: 200,
        body: '{"status":"Succeeded"}',
        headers: {}
      )
    end

    context 'dual-stack NIC with IPv4 + IPv6 ipConfigurations' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: { 'user-agent' => 'bosh' },
          enable_ip_forwarding: false,
          enable_accelerated_networking: true,
          network_security_group: { id: nsg_id },
          application_security_groups: [{ id: 'fake-asg-id' }],
          dns_servers: nil,
          public_ip: { id: 'fake-public-ip-id' },
          load_balancers: nil,
          application_gateways: nil,
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.5'
            },
            {
              name: 'ipconfig0-1',
              ip_version: 'IPv6',
              subnet: subnet,
              private_ip: 'fd00::5'
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: { 'user-agent' => 'bosh' },
          properties: {
            networkSecurityGroup: { id: nsg_id },
            enableIPForwarding: false,
            enableAcceleratedNetworking: true,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.5',
                  publicIPAddress: { id: 'fake-public-ip-id' },
                  applicationSecurityGroups: [{ id: 'fake-asg-id' }]
                }
              },
              {
                name: 'ipconfig0-1',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv6',
                  subnet: { id: subnet[:id] },
                  primary: false,
                  privateIPAddress: 'fd00::5',
                  applicationSecurityGroups: [{ id: 'fake-asg-id' }]
                }
              }
            ],
            dnsSettings: {
              dnsServers: []
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'creates a NIC with a primary IPv4 ipConfiguration carrying the public IP and a secondary IPv6 ipConfiguration, with ASGs attached to both' do
        # The webmock stub above pins the exact request body, so any drift in
        # primary flags, public-IP placement, or ASG attachment will fail here.
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end

    context 'dual-stack NIC with load balancer (separate IPv4/IPv6 backend pools)' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          enable_ip_forwarding: false,
          enable_accelerated_networking: false,
          network_security_group: { id: nsg_id },
          application_security_groups: [],
          dns_servers: nil,
          public_ip: nil,
          load_balancers: [
            {
              backend_address_pools: [
                { name: 'pool-v4', id: 'fake-lb-pool-v4-id' }
              ],
              backend_address_pools_v6: [
                { name: 'pool-v6', id: 'fake-lb-pool-v6-id' }
              ],
              frontend_ip_configurations: [
                { inbound_nat_rules: [] }
              ]
            }
          ],
          application_gateways: nil,
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.5'
            },
            {
              name: 'ipconfig0-1',
              ip_version: 'IPv6',
              subnet: subnet,
              private_ip: 'fd00::5'
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          properties: {
            networkSecurityGroup: { id: nsg_id },
            enableIPForwarding: false,
            enableAcceleratedNetworking: false,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.5',
                  loadBalancerBackendAddressPools: [{ id: 'fake-lb-pool-v4-id' }]
                }
              },
              {
                name: 'ipconfig0-1',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv6',
                  subnet: { id: subnet[:id] },
                  primary: false,
                  privateIPAddress: 'fd00::5',
                  loadBalancerBackendAddressPools: [{ id: 'fake-lb-pool-v6-id' }]
                }
              }
            ],
            dnsSettings: {
              dnsServers: []
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'routes each ipConfig to the matching IP-family backend pool with NAT rules only on the IPv4 primary' do
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end

    context 'dual-stack NIC with application gateway (IPv4-only backend)' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          enable_ip_forwarding: false,
          enable_accelerated_networking: false,
          network_security_group: nil,
          application_security_groups: [],
          dns_servers: nil,
          public_ip: nil,
          load_balancers: nil,
          application_gateways: [
            {
              backend_address_pools: [
                { name: 'agw-pool', id: 'fake-agw-pool-id' }
              ]
            }
          ],
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.5'
            },
            {
              name: 'ipconfig0-1',
              ip_version: 'IPv6',
              subnet: subnet,
              private_ip: 'fd00::5'
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          properties: {
            networkSecurityGroup: nil,
            enableIPForwarding: false,
            enableAcceleratedNetworking: false,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.5',
                  applicationGatewayBackendAddressPools: [{ id: 'fake-agw-pool-id' }]
                }
              },
              {
                name: 'ipconfig0-1',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv6',
                  subnet: { id: subnet[:id] },
                  primary: false,
                  privateIPAddress: 'fd00::5'
                }
              }
            ],
            dnsSettings: {
              dnsServers: []
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'should attach AGW backend pool only to IPv4 ipConfiguration, not IPv6' do
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end

    context 'dual-stack NIC with dynamic IPv6 allocation (no private_ip)' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          enable_ip_forwarding: false,
          enable_accelerated_networking: false,
          network_security_group: nil,
          application_security_groups: [],
          dns_servers: nil,
          public_ip: nil,
          load_balancers: nil,
          application_gateways: nil,
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.5'
            },
            {
              name: 'ipconfig0-1',
              ip_version: 'IPv6',
              subnet: subnet,
              private_ip: nil
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          properties: {
            networkSecurityGroup: nil,
            enableIPForwarding: false,
            enableAcceleratedNetworking: false,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.5'
                }
              },
              {
                name: 'ipconfig0-1',
                properties: {
                  privateIPAllocationMethod: 'Dynamic',
                  privateIPAddressVersion: 'IPv6',
                  subnet: { id: subnet[:id] },
                  primary: false
                }
              }
            ],
            dnsSettings: {
              dnsServers: []
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'should use Dynamic allocation for IPv6 when no private_ip is specified' do
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end

    context 'backward compatibility — single IPv4 ipConfiguration via ip_configurations array' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          enable_ip_forwarding: false,
          enable_accelerated_networking: false,
          network_security_group: nil,
          application_security_groups: [],
          dns_servers: nil,
          public_ip: nil,
          load_balancers: nil,
          application_gateways: nil,
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.100'
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: {},
          properties: {
            networkSecurityGroup: nil,
            enableIPForwarding: false,
            enableAcceleratedNetworking: false,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.100'
                }
              }
            ],
            dnsSettings: {
              dnsServers: []
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'should produce identical payload to legacy single-ipconfig path' do
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end

    context 'dual-stack + LB + AGW + ASG combined' do
      let(:nic_params) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: { 'user-agent' => 'bosh' },
          enable_ip_forwarding: true,
          enable_accelerated_networking: true,
          network_security_group: { id: nsg_id },
          application_security_groups: [{ id: 'fake-asg-1' }, { id: 'fake-asg-2' }],
          dns_servers: ['168.63.129.16'],
          public_ip: { id: 'fake-public-ip-id' },
          load_balancers: [
            {
              backend_address_pools: [
                { name: 'pool-v4', id: 'fake-lb-v4-id' }
              ],
              backend_address_pools_v6: [
                { name: 'pool-v6', id: 'fake-lb-v6-id' }
              ],
              frontend_ip_configurations: [
                { inbound_nat_rules: [{ id: 'fake-nat-rule-id' }] }
              ]
            }
          ],
          application_gateways: [
            {
              backend_address_pools: [
                { name: 'agw-pool', id: 'fake-agw-pool-id' }
              ]
            }
          ],
          ip_configurations: [
            {
              name: 'ipconfig0-0',
              ip_version: 'IPv4',
              subnet: subnet,
              private_ip: '10.0.0.5'
            },
            {
              name: 'ipconfig0-1',
              ip_version: 'IPv6',
              subnet: subnet,
              private_ip: 'fd00::5'
            }
          ]
        }
      end

      let(:expected_request_body) do
        {
          name: nic_name,
          location: 'westeurope',
          tags: { 'user-agent' => 'bosh' },
          properties: {
            networkSecurityGroup: { id: nsg_id },
            enableIPForwarding: true,
            enableAcceleratedNetworking: true,
            ipConfigurations: [
              {
                name: 'ipconfig0-0',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv4',
                  subnet: { id: subnet[:id] },
                  primary: true,
                  privateIPAddress: '10.0.0.5',
                  publicIPAddress: { id: 'fake-public-ip-id' },
                  loadBalancerBackendAddressPools: [{ id: 'fake-lb-v4-id' }],
                  loadBalancerInboundNatRules: [{ id: 'fake-nat-rule-id' }],
                  applicationGatewayBackendAddressPools: [{ id: 'fake-agw-pool-id' }],
                  applicationSecurityGroups: [{ id: 'fake-asg-1' }, { id: 'fake-asg-2' }]
                }
              },
              {
                name: 'ipconfig0-1',
                properties: {
                  privateIPAllocationMethod: 'Static',
                  privateIPAddressVersion: 'IPv6',
                  subnet: { id: subnet[:id] },
                  primary: false,
                  privateIPAddress: 'fd00::5',
                  loadBalancerBackendAddressPools: [{ id: 'fake-lb-v6-id' }],
                  applicationSecurityGroups: [{ id: 'fake-asg-1' }, { id: 'fake-asg-2' }]
                }
              }
            ],
            dnsSettings: {
              dnsServers: ['168.63.129.16']
            }
          }
        }
      end

      before { stub_create_nic(expected_request_body) }

      it 'should correctly distribute LB pools, AGW, ASGs, and public IP across IPv4/IPv6 ipConfigs' do
        expect { azure_client.create_network_interface(resource_group, nic_params) }.not_to raise_error
      end
    end
  end

  describe '#parse_network_interface — dual-stack NIC response' do
    let(:dual_stack_nic_response) do
      {
        'id' => '/subscriptions/fake-sub/resourceGroups/fake-rg/providers/Microsoft.Network/networkInterfaces/vm-abc-0',
        'name' => 'vm-abc-0',
        'location' => 'westeurope',
        'tags' => { 'user-agent' => 'bosh' },
        'properties' => {
          'provisioningState' => 'Succeeded',
          'enableIPForwarding' => false,
          'enableAcceleratedNetworking' => true,
          'dnsSettings' => { 'dnsServers' => [] },
          'ipConfigurations' => [
            {
              'id' => '/subscriptions/fake-sub/.../ipconfig0-0',
              'name' => 'ipconfig0-0',
              'properties' => {
                'primary' => true,
                'privateIPAddress' => '10.0.0.5',
                'privateIPAllocationMethod' => 'Static',
                'privateIPAddressVersion' => 'IPv4',
                'subnet' => { 'id' => 'fake-subnet-id' },
                'publicIPAddress' => { 'id' => 'fake-public-ip-id' },
                'loadBalancerBackendAddressPools' => [
                  { 'id' => '/subscriptions/fake-sub/.../backendAddressPools/pool-v4' }
                ],
                'applicationGatewayBackendAddressPools' => [
                  { 'id' => '/subscriptions/fake-sub/.../backendAddressPools/agw-pool' }
                ],
                'applicationSecurityGroups' => [
                  { 'id' => 'fake-asg-id' }
                ]
              }
            },
            {
              'id' => '/subscriptions/fake-sub/.../ipconfig0-1',
              'name' => 'ipconfig0-1',
              'properties' => {
                'primary' => false,
                'privateIPAddress' => 'fd00::5',
                'privateIPAllocationMethod' => 'Static',
                'privateIPAddressVersion' => 'IPv6',
                'subnet' => { 'id' => 'fake-subnet-id' },
                'loadBalancerBackendAddressPools' => [
                  { 'id' => '/subscriptions/fake-sub/.../backendAddressPools/pool-v6' }
                ],
                'applicationSecurityGroups' => [
                  { 'id' => 'fake-asg-id' }
                ]
              }
            }
          ]
        }
      }
    end

    subject(:result) { azure_client.send(:parse_network_interface, dual_stack_nic_response, recursive: false) }
    let(:ipv4_config) { result[:ip_configurations].find { |c| c[:primary] } }
    let(:ipv6_config) { result[:ip_configurations].find { |c| !c[:primary] } }

    it 'parses both ipConfigurations with the correct IP family, primary flag, and address' do
      expect(result[:ip_configurations].length).to eq(2)

      expect(ipv4_config).to include(
        name: 'ipconfig0-0',
        private_ip: '10.0.0.5',
        private_ip_address_version: 'IPv4'
      )
      expect(ipv6_config).to include(
        name: 'ipconfig0-1',
        private_ip: 'fd00::5',
        private_ip_address_version: 'IPv6'
      )
    end

    it 'distributes public IP, LB pools, AGW pools, and ASGs across the matching ipConfigs' do
      # Public IP and AGW are IPv4-only; LB has per-family pools; ASGs apply to both.
      expect(ipv4_config[:public_ip]).to eq(id: 'fake-public-ip-id')
      expect(ipv6_config[:public_ip]).to be_nil

      expect(ipv4_config[:load_balancers].map { |lb| lb[:id] }).to all(include('pool-v4'))
      expect(ipv6_config[:load_balancers].map { |lb| lb[:id] }).to all(include('pool-v6'))

      expect(ipv4_config[:application_gateways].length).to eq(1)
      expect(ipv6_config[:application_gateways]).to be_nil

      [ipv4_config, ipv6_config].each do |config|
        expect(config[:application_security_groups]).to eq([{ id: 'fake-asg-id' }])
      end
    end

    it 'exposes backward-compatible top-level accessors from the primary (IPv4) config' do
      expect(result[:private_ip]).to eq('10.0.0.5')
      expect(result[:public_ip]).to eq(id: 'fake-public-ip-id')
    end
  end
end
