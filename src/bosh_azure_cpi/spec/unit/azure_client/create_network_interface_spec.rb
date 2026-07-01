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

      context 'with multiple ip_configurations and a public IP' do
        let(:nic_params) do
          {
            name: nic_name,
            location: 'fake-location',
            tags: {},
            enable_ip_forwarding: false,
            enable_accelerated_networking: false,
            dns_servers: nil,
            public_ip: { id: 'fake-public-ip-id', public_ip_address_version: 'IPv4' },
            network_security_group: { id: nsg_id },
            application_security_groups: [],
            load_balancers: nil,
            application_gateways: nil,
            ip_configurations: [
              { name: 'ipconfig0-0', ip_version: 'IPv6', subnet: subnet, private_ip: 'fd00::5' },
              { name: 'ipconfig0-1', ip_version: 'IPv4', subnet: subnet, private_ip: '10.0.0.5' }
            ]
          }
        end
        let(:request_body) do
          {
            name: nic_name,
            location: 'fake-location',
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
                    privateIPAddressVersion: 'IPv6',
                    subnet: { id: subnet[:id] },
                    primary: true,
                    privateIPAddress: 'fd00::5'
                  }
                },
                {
                  name: 'ipconfig0-1',
                  properties: {
                    privateIPAllocationMethod: 'Static',
                    privateIPAddressVersion: 'IPv4',
                    subnet: { id: subnet[:id] },
                    primary: false,
                    privateIPAddress: '10.0.0.5',
                    publicIPAddress: { id: 'fake-public-ip-id' }
                  }
                }
              ],
              dnsSettings: { dnsServers: [] }
            }
          }
        end

        it 'attaches the public IP to the ipConfig whose family matches, regardless of order' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: { 'access_token' => valid_access_token, 'expires_on' => expires_on }.to_json,
            headers: {}
          )
          stub_request(:put, network_interface_uri)
            .with(body: request_body.to_json)
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

          expect do
            azure_client.create_network_interface(resource_group, nic_params)
          end.not_to raise_error
        end
      end

      context 'when a public IP has no ipConfiguration of the matching address family' do
        let(:nic_params) do
          {
            public_ip: { id: 'fake-public-ip-id', public_ip_address_version: 'IPv6' },
            ip_configurations: [
              { name: 'ipconfig0-0', ip_version: 'IPv4', subnet: subnet, private_ip: '10.0.0.5' }
            ]
          }
        end

        it 'raises an error instead of silently dropping the public IP' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {}.to_json,
            headers: {}
          )

          expect do
            azure_client.create_network_interface(resource_group, nic_params)
          end.to raise_error(Bosh::AzureCloud::AzureError, /no ipConfiguration matches the public IP address version 'IPv6'/)
          expect(a_request(:put, network_interface_uri)).not_to have_been_made
        end
      end
    end
  end

end
