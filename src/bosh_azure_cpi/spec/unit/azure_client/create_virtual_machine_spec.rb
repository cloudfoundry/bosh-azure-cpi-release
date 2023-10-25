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
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { 'fake-vm-name' }
  let(:valid_access_token) { 'valid-access-token' }

  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_virtual_machine' do
    let(:vm_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}&validating=true" }

    let(:vm_params) do
      {
        name: vm_name,
        location: 'b',
        tags: { 'foo' => 'bar' },
        vm_size: 'c',
        ssh_username: 'd',
        ssh_cert_data: 'e',
        custom_data: 'f',
        image_uri: 'g',
        os_disk: {
          disk_name: 'h',
          disk_uri: 'i',
          disk_caching: 'j',
          disk_size: 'k'
        },
        ephemeral_disk: {
          disk_name: 'l',
          disk_uri: 'm',
          disk_caching: 'n',
          disk_size: 'o'
        },
        os_type: 'linux',
        managed: false
      }
    end

    let(:network_interfaces) do
      [
        { id: 'a' },
        { id: 'b' }
      ]
    end

    context 'parse the parameters' do
      context 'when identity is not nil' do
        context 'when identity is system assigned identity' do
          let(:vm_params_system_assigned_identity) do
            vm_params_dupped = vm_params.dup
            vm_params_dupped[:managed] = false
            vm_params_dupped[:identity] = {
              type: 'SystemAssigned'
            }
            vm_params_dupped
          end

          let(:request_body) do
            {
              name: vm_name,
              location: 'b',
              type: 'Microsoft.Compute/virtualMachines',
              tags: {
                foo: 'bar'
              },
              identity: {
                type: 'SystemAssigned'
              },
              properties: {
                hardwareProfile: {
                  vmSize: 'c'
                },
                osProfile: {
                  customData: 'f',
                  computerName: vm_name,
                  adminUsername: 'd',
                  linuxConfiguration: {
                    disablePasswordAuthentication: 'true',
                    ssh: {
                      publicKeys: [
                        {
                          path: '/home/d/.ssh/authorized_keys',
                          keyData: 'e'
                        }
                      ]
                    }
                  }
                },
                networkProfile: {
                  networkInterfaces: [
                    {
                      id: 'a',
                      properties: {
                        primary: true
                      }
                    },
                    {
                      id: 'b',
                      properties: {
                        primary: false
                      }
                    }
                  ]
                },
                storageProfile: {
                  osDisk: {
                    name: 'h',
                    osType: 'linux',
                    createOption: 'FromImage',
                    caching: 'j',
                    image: {
                      uri: 'g'
                    },
                    vhd: {
                      uri: 'i'
                    },
                    diskSizeGB: 'k'
                  },
                  dataDisks: [
                    {
                      name: 'l',
                      lun: 0,
                      createOption: 'Empty',
                      diskSizeGB: 'o',
                      vhd: {
                        uri: 'm'
                      },
                      caching: 'n'
                    }
                  ]
                }
              }
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
            stub_request(:put, vm_uri).with(body: request_body).to_return(
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
              azure_client.create_virtual_machine(resource_group, vm_params_system_assigned_identity, network_interfaces)
            end.not_to raise_error
          end
        end

        context 'when identity is user assigned identity' do
          let(:vm_params_user_assigned_identity) do
            vm_params_dupped = vm_params.dup
            vm_params_dupped[:managed] = false
            vm_params_dupped[:identity] = {
              type: 'UserAssigned',
              identity_name: 'fake-identity-name'
            }
            vm_params_dupped
          end

          let(:request_body) do
            {
              name: vm_name,
              location: 'b',
              type: 'Microsoft.Compute/virtualMachines',
              tags: {
                foo: 'bar'
              },
              identity: {
                type: 'UserAssigned',
                userAssignedIdentities: { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/fake-identity-name": {} }
              },
              properties: {
                hardwareProfile: {
                  vmSize: 'c'
                },
                osProfile: {
                  customData: 'f',
                  computerName: vm_name,
                  adminUsername: 'd',
                  linuxConfiguration: {
                    disablePasswordAuthentication: 'true',
                    ssh: {
                      publicKeys: [
                        {
                          path: '/home/d/.ssh/authorized_keys',
                          keyData: 'e'
                        }
                      ]
                    }
                  }
                },
                networkProfile: {
                  networkInterfaces: [
                    {
                      id: 'a',
                      properties: {
                        primary: true
                      }
                    },
                    {
                      id: 'b',
                      properties: {
                        primary: false
                      }
                    }
                  ]
                },
                storageProfile: {
                  osDisk: {
                    name: 'h',
                    osType: 'linux',
                    createOption: 'FromImage',
                    caching: 'j',
                    image: {
                      uri: 'g'
                    },
                    vhd: {
                      uri: 'i'
                    },
                    diskSizeGB: 'k'
                  },
                  dataDisks: [
                    {
                      name: 'l',
                      lun: 0,
                      createOption: 'Empty',
                      diskSizeGB: 'o',
                      vhd: {
                        uri: 'm'
                      },
                      caching: 'n'
                    }
                  ]
                }
              }
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
            stub_request(:put, vm_uri).with(body: request_body).to_return(
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
              azure_client.create_virtual_machine(resource_group, vm_params_user_assigned_identity, network_interfaces)
            end.not_to raise_error
          end
        end
      end

      context 'when managed is false' do
        let(:vm_params_magaged_false) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped[:managed] = false
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    vhd: {
                      uri: 'm'
                    },
                    caching: 'n'
                  }
                ]
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_magaged_false, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when managed is true' do
        let(:vm_params_managed) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped.delete(:image_uri)
          vm_params_dupped[:image_id] = 'g'
          vm_params_dupped[:managed] = true
          vm_params_dupped[:os_disk].delete(:disk_uri)
          vm_params_dupped[:ephemeral_disk].delete(:disk_uri)
          vm_params_dupped[:ephemeral_disk][:disk_type] = 'p'
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                imageReference: {
                  id: 'g'
                },
                osDisk: {
                  name: 'h',
                  createOption: 'FromImage',
                  caching: 'j',
                  diskSizeGB: 'k'
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    caching: 'n',
                    managedDisk: {
                      storageAccountType: 'p'
                    }
                  }
                ]
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_managed, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when os_disk.disk_size is nil' do
        let(:vm_params_without_os_disk_size) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped[:os_disk].delete(:disk_size)
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  }
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    vhd: {
                      uri: 'm'
                    },
                    caching: 'n'
                  }
                ]
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_without_os_disk_size, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'When the ephemeral disk is nil' do
        let(:vm_params_without_ephemeral_disk) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped.delete(:ephemeral_disk)
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                }
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_without_ephemeral_disk, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when availability set is not nil' do
        let(:availability_set) do
          {
            id: 'a'
          }
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    vhd: {
                      uri: 'm'
                    },
                    caching: 'n'
                  }
                ]
              },
              availabilitySet: {
                id: 'a'
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces, availability_set)
          end.not_to raise_error
        end
      end

      context 'when image_reference is not nil' do
        let(:image_reference) do
          {
            'publisher' => 'p',
            'offer' => 'q',
            'sku' => 'r',
            'version' => 's'
          }
        end
        let(:vm_params_with_image_reference) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped[:image_reference] = image_reference
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                imageReference: image_reference,
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    vhd: {
                      uri: 'm'
                    },
                    caching: 'n'
                  }
                ]
              }
            },
            plan: {
              name: image_reference['sku'],
              publisher: image_reference['publisher'],
              product: image_reference['offer']
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_with_image_reference, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when os_type is windows' do
        let(:logger_strio) { StringIO.new }
        let(:windows_password) { 'THISISWINDOWSCREDENTIAL' }
        let(:vm_params_windows) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped.delete(:ssh_username)
          vm_params_dupped.delete(:ssh_cert_data)
          vm_params_dupped[:os_type] = 'windows'
          vm_params_dupped[:windows_username] = 'd'
          vm_params_dupped[:windows_password] = windows_password
          vm_params_dupped.delete(:ephemeral_disk)
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                adminPassword: windows_password,
                windowsConfiguration: {
                  enableAutomaticUpdates: false
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'windows',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                }
              }
            }
          }
        end

        let(:response_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                adminPassword: windows_password,
                windowsConfiguration: {
                  enableAutomaticUpdates: false
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'windows',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                },
                dataDisks: []
              }
            }
          }
        end

        context 'redact credentials in logs' do
          let(:azure_client) do
            Bosh::AzureCloud::AzureClient.new(
              mock_azure_config,
              Logger.new(logger_strio)
            )
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
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              status: 200,
              body: response_body.to_json.to_s,
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
              azure_client.create_virtual_machine(resource_group, vm_params_windows, network_interfaces)
            end.not_to raise_error

            logs = logger_strio.string
            expect(logs.include?(windows_password)).to be(false)
            expect(logs.include?(MOCK_AZURE_CLIENT_SECRET)).to be(false)
            expect(logs.scan('<redacted>').count).to eq(5)
          end
        end

        context 'do not redact credentials in logs' do
          let(:azure_client) do
            Bosh::AzureCloud::AzureClient.new(
              mock_azure_config_merge('debug_mode' => true),
              Logger.new(logger_strio)
            )
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
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              status: 200,
              body: response_body.to_json.to_s,
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
              azure_client.create_virtual_machine(resource_group, vm_params_windows, network_interfaces)
            end.not_to raise_error

            logs = logger_strio.string
            expect(logs.include?(windows_password)).to be(true)
            expect(logs.include?(MOCK_AZURE_CLIENT_SECRET)).to be(true)
            expect(logs.include?('<redacted>')).to be(false)
          end
        end
      end

      context 'When diag_storage_uri is not nil' do
        let(:diag_storage_uri) { 'fake-diag-storage-uri' }
        let(:vm_params_with_diag_storage_uri) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped.delete(:ephemeral_disk)
          vm_params_dupped[:diag_storage_uri] = diag_storage_uri
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  },
                  diskSizeGB: 'k'
                }
              },
              diagnosticsProfile: { # boot diagnostics
                bootDiagnostics: {
                  enabled: true,
                  storageUri: diag_storage_uri
                }
              }
            }
          }
        end

        it 'should create the vm with boot diagnostics enabled' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_with_diag_storage_uri, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when zone is not nil' do
        let(:vm_params_with_zone) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped.delete(:ephemeral_disk)
          vm_params_dupped.delete(:image_uri)
          vm_params_dupped[:image_id] = 'g'
          vm_params_dupped[:managed] = true
          vm_params_dupped[:zone] = 'm'
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            zones: ['m'],
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: vm_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                imageReference: {
                  id: 'g'
                },
                osDisk: {
                  name: 'h',
                  createOption: 'FromImage',
                  caching: 'j',
                  diskSizeGB: 'k'
                }
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_with_zone, network_interfaces)
          end.not_to raise_error
        end
      end

      context 'when os_type is invalid' do
        let(:vm_params_invalid_os_type) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped[:os_type] = 'fake-os-type'
          vm_params_dupped
        end

        it 'should reaise error' do
          expect do
            azure_client.create_virtual_machine(resource_group, vm_params_invalid_os_type, network_interfaces)
          end.to raise_error(/Unsupported os type/)
        end
      end

      context 'when computer_name is set' do
        let(:computer_name) { 'fake-computer-name' }
        let(:vm_params_with_compute_name) do
          vm_params_dupped = vm_params.dup
          vm_params_dupped[:os_disk].delete(:disk_size)
          vm_params_dupped[:computer_name] = computer_name
          vm_params_dupped
        end

        let(:request_body) do
          {
            name: vm_name,
            location: 'b',
            type: 'Microsoft.Compute/virtualMachines',
            tags: {
              foo: 'bar'
            },
            properties: {
              hardwareProfile: {
                vmSize: 'c'
              },
              osProfile: {
                customData: 'f',
                computerName: computer_name,
                adminUsername: 'd',
                linuxConfiguration: {
                  disablePasswordAuthentication: 'true',
                  ssh: {
                    publicKeys: [
                      {
                        path: '/home/d/.ssh/authorized_keys',
                        keyData: 'e'
                      }
                    ]
                  }
                }
              },
              networkProfile: {
                networkInterfaces: [
                  {
                    id: 'a',
                    properties: {
                      primary: true
                    }
                  },
                  {
                    id: 'b',
                    properties: {
                      primary: false
                    }
                  }
                ]
              },
              storageProfile: {
                osDisk: {
                  name: 'h',
                  osType: 'linux',
                  createOption: 'FromImage',
                  caching: 'j',
                  image: {
                    uri: 'g'
                  },
                  vhd: {
                    uri: 'i'
                  }
                },
                dataDisks: [
                  {
                    name: 'l',
                    lun: 0,
                    createOption: 'Empty',
                    diskSizeGB: 'o',
                    vhd: {
                      uri: 'm'
                    },
                    caching: 'n'
                  }
                ]
              }
            }
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
          stub_request(:put, vm_uri).with(body: request_body).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params_with_compute_name, network_interfaces)
          end.not_to raise_error
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
          stub_request(:put, vm_uri).to_return(
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
            azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
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
          stub_request(:put, vm_uri).to_return(
            status: 401,
            body: '',
            headers: {}
          )

          expect do
            azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
          end.to raise_error(/Azure authentication failed: Token is invalid./)
        end
      end
    end

    context 'when another process is operating the same VM' do
      it 'should raise AzureConflictError' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, vm_uri).to_return(
          status: 409,
          body: 'Another process is operating the same VM',
          headers: {}
        )

        expect do
          azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
        end.to raise_error Bosh::AzureCloud::AzureConflictError
      end
    end

    context 'when network interface count exceeds the max allowed NIC number' do
      it 'should raise AzureError' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, vm_uri).to_return(
          status: 400,
          body: 'The number of network interfaces for virtual machine xxx exceeds the maximum allowed for the virtual machine size Standard_D1.',
          headers: {}
        )

        expect do
          azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
        end.to raise_error(/The number of network interfaces for virtual machine xxx exceeds the maximum/)
      end
    end

    context 'when token is valid, create operation is accepted and not completed' do
      it 'should raise an error if check completion operation is not accepeted' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
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
          status: 404,
          body: '',
          headers: {}
        )

        expect do
          azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
        end.to raise_error(/check_completion - http code: 404/)
      end

      it 'should raise an error if create operation failed' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
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
          body: '{"status":"Cancelled"}',
          headers: {}
        )

        expect do
          azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
        end.to(raise_error { |error| expect(error.status).to eq('Cancelled') })
      end
    end

    context 'when token is valid, create operation is accepted and completed' do
      it 'should raise no error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
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
          azure_client.create_virtual_machine(resource_group, vm_params, network_interfaces)
        end.not_to raise_error
      end
    end
  end
end
