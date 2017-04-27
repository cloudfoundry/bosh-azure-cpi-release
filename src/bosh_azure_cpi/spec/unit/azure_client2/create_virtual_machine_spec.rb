require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient2 do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client2) {
    Bosh::AzureCloud::AzureClient2.new(
      mock_cloud_options["properties"]["azure"],
      logger
    )
  }
  let(:subscription_id) { mock_azure_properties['subscription_id'] }
  let(:tenant_id) { mock_azure_properties['tenant_id'] }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:resource_group) { mock_azure_properties['resource_group_name'] }
  let(:request_id) { "fake-request-id" }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { "fake-vm-name" }
  let(:valid_access_token) { "valid-access-token" }

  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#create_virtual_machine" do
    let(:vm_uri) { "https://management.azure.com//subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}&validating=true" }

    let(:vm_params) do
      {
        :name           => vm_name,
        :location       => "b",
        :tags           => { "foo" => "bar"},
        :vm_size        => "c",
        :ssh_username   => "d",
        :ssh_cert_data  => "e",
        :custom_data    => "f",
        :image_uri      => "g",
        :os_disk        => {
          :disk_name     => "h",
          :disk_uri      => "i",
          :disk_caching  => "j",
          :disk_size     => "k",
        },
        :ephemeral_disk => {
          :disk_name     => "l",
          :disk_uri      => "m",
          :disk_caching  => "n",
          :disk_size     => "o",
        },
        :os_type        => "linux",
        :managed        => false
      }
    end

    let(:network_interfaces) do
      [
        {:id => "a"},
        {:id => "b"}
      ]
    end

    context "parse the parameters" do
      context "common vm_params are provided" do
        context "when managed is false" do
          let(:vm_params) do
            {
              :name           => vm_name,
              :location       => "b",
              :tags           => { "foo" => "bar"},
              :vm_size        => "c",
              :ssh_username   => "d",
              :ssh_cert_data  => "e",
              :custom_data    => "f",
              :image_uri      => "g",
              :os_disk        => {
                :disk_name     => "h",
                :disk_uri      => "i",
                :disk_caching  => "j",
                :disk_size     => "k",
              },
              :ephemeral_disk => {
                :disk_name     => "l",
                :disk_uri      => "m",
                :disk_caching  => "n",
                :disk_size     => "o",
              },
              :os_type        => "linux",
              :managed        => false
            }
          end

          let(:request_body) {
            {
              :name     => vm_name,
              :location => "b",
              :type     => "Microsoft.Compute/virtualMachines",
              :tags     => {
                :foo => "bar"
              },
              :properties => {
                :hardwareProfile => {
                  :vmSize => "c"
                },
                :osProfile => {
                  :customData => "f",
                  :computerName => vm_name,
                  :adminUsername => "d",
                  :linuxConfiguration => {
                    :disablePasswordAuthentication => "true",
                    :ssh => {
                      :publicKeys => [
                        {
                          :path => "/home/d/.ssh/authorized_keys",
                          :keyData => "e"
                        }
                      ]
                    }
                  }
                },
                :networkProfile => {
                  :networkInterfaces => [
                    {
                      :id => "a",
                      :properties => {
                        :primary => true
                      }
                    },
                    {
                      :id => "b",
                      :properties => {
                        :primary => false
                      }
                    }
                  ]
                },
                :storageProfile => {
                  :osDisk => {
                    :name => "h",
                    :osType => "linux",
                    :createOption => "FromImage",
                    :caching => "j",
                    :image => {
                      :uri => "g"
                    },
                    :vhd => {
                      :uri => "i"
                    },
                    :diskSizeGB => "k"
                  },
                  :dataDisks => [
                    {
                      :name => "l",
                      :lun  => 0,
                      :createOption => "Empty",
                      :diskSizeGB => "o",
                      :vhd => {
                        :uri => "m"
                      },
                      :caching => "n"
                    }
                  ]
                }
              }
            }
          }

          it "should raise no error" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              })
            stub_request(:get, operation_status_link).to_return(
              :status => 200,
              :body => '{"status":"Succeeded"}',
              :headers => {})

            expect {
              azure_client2.create_virtual_machine(vm_params, network_interfaces)
            }.not_to raise_error
          end
        end

        context "when managed is true" do
          let(:vm_params_managed) do
            {
              :name           => vm_name,
              :location       => "b",
              :tags           => { "foo" => "bar"},
              :vm_size        => "c",
              :ssh_username   => "d",
              :ssh_cert_data  => "e",
              :custom_data    => "f",
              :image_id       => "g",
              :os_disk        => {
                :disk_name     => "h",
                :disk_caching  => "j",
                :disk_size     => "k",
              },
              :ephemeral_disk => {
                :disk_name     => "l",
                :disk_caching  => "n",
                :disk_size     => "o",
              },
              :os_type        => "linux",
              :managed        => true
            }
          end

          let(:request_body) {
            {
              :name     => vm_name,
              :location => "b",
              :type     => "Microsoft.Compute/virtualMachines",
              :tags     => {
                :foo => "bar"
              },
              :properties => {
                :hardwareProfile => {
                  :vmSize => "c"
                },
                :osProfile => {
                  :customData => "f",
                  :computerName => vm_name,
                  :adminUsername => "d",
                  :linuxConfiguration => {
                    :disablePasswordAuthentication => "true",
                    :ssh => {
                      :publicKeys => [
                        {
                          :path => "/home/d/.ssh/authorized_keys",
                          :keyData => "e"
                        }
                      ]
                    }
                  }
                },
                :networkProfile => {
                  :networkInterfaces => [
                    {
                      :id => "a",
                      :properties => {
                        :primary => true
                      }
                    },
                    {
                      :id => "b",
                      :properties => {
                        :primary => false
                      }
                    }
                  ]
                },
                :storageProfile => {
                  :imageReference => {
                    :id => "g"
                  },
                  :osDisk => {
                    :name => "h",
                    :createOption => "FromImage",
                    :caching => "j",
                    :diskSizeGB => "k"
                  },
                  :dataDisks => [
                    {
                      :name => "l",
                      :lun  => 0,
                      :createOption => "Empty",
                      :diskSizeGB => "o",
                      :caching => "n"
                    }
                  ]
                }
              }
            }
          }

          it "should raise no error" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              })
            stub_request(:get, operation_status_link).to_return(
              :status => 200,
              :body => '{"status":"Succeeded"}',
              :headers => {})

            expect {
              azure_client2.create_virtual_machine(vm_params_managed, network_interfaces)
            }.not_to raise_error
          end
        end
      end

      context "when os_disk.disk_size is nil" do
        let(:vm_params) do
          {
            :name           => vm_name,
            :location       => "b",
            :tags           => { "foo" => "bar"},
            :vm_size        => "c",
            :ssh_username   => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j"
            },
            :ephemeral_disk => {
              :disk_name     => "l",
              :disk_uri      => "m",
              :disk_caching  => "n",
              :disk_size     => "o",
            },
            :os_type        => "linux",
            :managed        => false     # true or false doen't matter in this case
          }
        end

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => vm_name,
                :adminUsername => "d",
                :linuxConfiguration => {
                  :disablePasswordAuthentication => "true",
                  :ssh => {
                    :publicKeys => [
                      {
                        :path => "/home/d/.ssh/authorized_keys",
                        :keyData => "e"
                      }
                    ]
                  }
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :osDisk => {
                  :name => "h",
                  :osType => "linux",
                  :createOption => "FromImage",
                  :caching => "j",
                  :image => {
                    :uri => "g"
                  },
                  :vhd => {
                    :uri => "i"
                  }
                },
                :dataDisks => [
                  {
                    :name => "l",
                    :lun  => 0,
                    :createOption => "Empty",
                    :diskSizeGB => "o",
                    :vhd => {
                      :uri => "m"
                    },
                    :caching => "n"
                  }
                ]
              }
            }
          }
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "When the ephemeral disk is nil" do
        let(:vm_params) do
          {
            :name           => vm_name,
            :location       => "b",
            :tags           => { "foo" => "bar"},
            :vm_size        => "c",
            :ssh_username   => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j",
              :disk_size     => "k",
            },
            :os_type        => "linux",
            :managed        => false     # true or false doen't matter in this case
          }
        end

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => vm_name,
                :adminUsername => "d",
                :linuxConfiguration => {
                  :disablePasswordAuthentication => "true",
                  :ssh => {
                    :publicKeys => [
                      {
                        :path => "/home/d/.ssh/authorized_keys",
                        :keyData => "e"
                      }
                    ]
                  }
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :osDisk => {
                  :name => "h",
                  :osType => "linux",
                  :createOption => "FromImage",
                  :caching => "j",
                  :image => {
                    :uri => "g"
                  },
                  :vhd => {
                    :uri => "i"
                  },
                  :diskSizeGB => "k"
                }
              }
            }
          }
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "when availability set is not nil" do
        let(:vm_params) do
          {
            :name           => vm_name,
            :location       => "b",
            :tags           => { "foo" => "bar"},
            :vm_size        => "c",
            :ssh_username   => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j",
              :disk_size     => "k",
            },
            :ephemeral_disk => {
              :disk_name     => "l",
              :disk_uri      => "m",
              :disk_caching  => "n",
              :disk_size     => "o",
            },
            :os_type        => "linux",
            :managed        => false     # true or false doen't matter in this case
          }
        end

        let(:availability_set) do
          {
            :id => "a"
          }
        end

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => vm_name,
                :adminUsername => "d",
                :linuxConfiguration => {
                  :disablePasswordAuthentication => "true",
                  :ssh => {
                    :publicKeys => [
                      {
                        :path => "/home/d/.ssh/authorized_keys",
                        :keyData => "e"
                      }
                    ]
                  }
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :osDisk => {
                  :name => "h",
                  :osType => "linux",
                  :createOption => "FromImage",
                  :caching => "j",
                  :image => {
                    :uri => "g"
                  },
                  :vhd => {
                    :uri => "i"
                  },
                  :diskSizeGB => "k"
                },
                :dataDisks => [
                  {
                    :name => "l",
                    :lun  => 0,
                    :createOption => "Empty",
                    :diskSizeGB => "o",
                    :vhd => {
                      :uri => "m"
                    },
                    :caching => "n"
                  }
                ]
              },
              :availabilitySet => {
                :id => "a"
              }
            }
          }
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces, availability_set)
          }.not_to raise_error
        end
      end

      context "when image_reference is not nil" do
        let(:image_reference) {
          {
            'publisher'    => 'p',
            'offer'        => 'q',
            'sku'          => 'r',
            'version'      => 's'
          }
        }

        let(:vm_params) {
          {
            :name           => vm_name,
            :location       => "b",
            :tags           => { "foo" => "bar"},
            :vm_size        => "c",
            :ssh_username   => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j",
              :disk_size     => "k",
            },
            :ephemeral_disk => {
              :disk_name     => "l",
              :disk_uri      => "m",
              :disk_caching  => "n",
              :disk_size     => "o",
            },
            :os_type        => "linux",
            :managed        => false,     # true or false doen't matter in this case
            :image_reference => image_reference
          }
        }

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => vm_name,
                :adminUsername => "d",
                :linuxConfiguration => {
                  :disablePasswordAuthentication => "true",
                  :ssh => {
                    :publicKeys => [
                      {
                        :path => "/home/d/.ssh/authorized_keys",
                        :keyData => "e"
                      }
                    ]
                  }
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :imageReference => image_reference,
                :osDisk => {
                  :name => "h",
                  :osType => "linux",
                  :createOption => "FromImage",
                  :caching => "j",
                  :vhd => {
                    :uri => "i"
                  },
                  :diskSizeGB => "k"
                },
                :dataDisks => [
                  {
                    :name => "l",
                    :lun  => 0,
                    :createOption => "Empty",
                    :diskSizeGB => "o",
                    :vhd => {
                      :uri => "m"
                    },
                    :caching => "n"
                  }
                ]
              }
            },
            :plan => {
              :name => image_reference['sku'],
              :publisher => image_reference['publisher'],
              :product => image_reference['offer']
            }
          }
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "when os_type is windows" do
        let(:logger_strio) { StringIO.new }
        let(:windows_password) { 'THISISWINDOWSCREDENTIAL' }
        let(:vm_params) do
          {
            :name               => vm_name,
            :location           => "b",
            :tags               => { "foo" => "bar"},
            :vm_size            => "c",
            :windows_username   => "d",
            :windows_password   => windows_password,
            :custom_data        => "f",
            :image_uri          => "g",
            :os_disk            => {
              :disk_name         => "h",
              :disk_uri          => "i",
              :disk_caching      => "j",
              :disk_size         => "k",
            },
            :os_type            => "windows",
            :managed            => false     # true or false doen't matter in this case
          }
        end

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => vm_name,
                :adminUsername => "d",
                :adminPassword => windows_password,
                :windowsConfiguration => {
                  :enableAutomaticUpdates => false
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :osDisk => {
                  :name => "h",
                  :osType => "windows",
                  :createOption => "FromImage",
                  :caching => "j",
                  :image => {
                    :uri => "g"
                  },
                  :vhd => {
                    :uri => "i"
                  },
                  :diskSizeGB => "k"
                }
              }
            }
          }
        }

        context "redact credentials in logs" do
          let(:azure_client2) {
            Bosh::AzureCloud::AzureClient2.new(
              mock_cloud_options["properties"]["azure"],
              Logger.new(logger_strio)
            )
          }

          it "should raise no error" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              })
            stub_request(:get, operation_status_link).to_return(
              :status => 200,
              :body => '{"status":"Succeeded"}',
              :headers => {})

            expect {
              azure_client2.create_virtual_machine(vm_params, network_interfaces)
            }.not_to raise_error

            logs = logger_strio.string
            expect(logs.include?(windows_password)).to be(false)
            expect(logs.include?(MOCK_AZURE_CLIENT_SECRET)).to be(false)
            expect(logs.scan('<redacted>').count).to eq(2)
          end
        end

        context "do not redact credentials in logs" do
          let(:azure_client2) {
            Bosh::AzureCloud::AzureClient2.new(
              mock_cloud_options["properties"]["azure"].merge({ 'debug_mode' => true }),
              Logger.new(logger_strio)
            )
          }

          it "should raise no error" do
            stub_request(:post, token_uri).to_return(
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {})
            stub_request(:put, vm_uri).with(body: request_body).to_return(
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              })
            stub_request(:get, operation_status_link).to_return(
              :status => 200,
              :body => '{"status":"Succeeded"}',
              :headers => {})

            expect {
              azure_client2.create_virtual_machine(vm_params, network_interfaces)
            }.not_to raise_error

            logs = logger_strio.string
            expect(logs.include?(windows_password)).to be(true)
            expect(logs.include?(MOCK_AZURE_CLIENT_SECRET)).to be(true)
            expect(logs.include?('<redacted>')).to be(false)
          end
        end
      end

      context "when os_type is invalid" do
        let(:vm_params) do
          {
            :name               => vm_name,
            :location           => "b",
            :tags               => { "foo" => "bar"},
            :vm_size            => "c",
            :windows_username   => "d",
            :windows_password   => "e",
            :custom_data        => "f",
            :image_uri          => "g",
            :os_disk            => {
              :disk_name         => "h",
              :disk_uri          => "i",
              :disk_caching      => "j",
              :disk_size         => "k",
            },
            :os_type            => "fake-os-type",
            :managed            => false     # true or false doen't matter in this case
          }
        end

        it "should reaise error" do
          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.to raise_error /Unsupported os type/
        end
      end

      context "when computer_name is set" do
        let(:computer_name) { 'fake-computer-name' }
        let(:vm_params) do
          {
            :name           => vm_name,
            :computer_name  => computer_name,
            :location       => "b",
            :tags           => { "foo" => "bar"},
            :vm_size        => "c",
            :ssh_username   => "d",
            :ssh_cert_data  => "e",
            :custom_data    => "f",
            :image_uri      => "g",
            :os_disk        => {
              :disk_name     => "h",
              :disk_uri      => "i",
              :disk_caching  => "j"
            },
            :ephemeral_disk => {
              :disk_name     => "l",
              :disk_uri      => "m",
              :disk_caching  => "n",
              :disk_size     => "o",
            },
            :os_type        => "linux",
            :managed        => false     # true or false doen't matter in this case
          }
        end

        let(:request_body) {
          {
            :name     => vm_name,
            :location => "b",
            :type     => "Microsoft.Compute/virtualMachines",
            :tags     => {
              :foo => "bar"
            },
            :properties => {
              :hardwareProfile => {
                :vmSize => "c"
              },
              :osProfile => {
                :customData => "f",
                :computerName => computer_name,
                :adminUsername => "d",
                :linuxConfiguration => {
                  :disablePasswordAuthentication => "true",
                  :ssh => {
                    :publicKeys => [
                      {
                        :path => "/home/d/.ssh/authorized_keys",
                        :keyData => "e"
                      }
                    ]
                  }
                }
              },
              :networkProfile => {
                :networkInterfaces => [
                  {
                    :id => "a",
                    :properties => {
                      :primary => true
                    }
                  },
                  {
                    :id => "b",
                    :properties => {
                      :primary => false
                    }
                  }
                ]
              },
              :storageProfile => {
                :osDisk => {
                  :name => "h",
                  :osType => "linux",
                  :createOption => "FromImage",
                  :caching => "j",
                  :image => {
                    :uri => "g"
                  },
                  :vhd => {
                    :uri => "i"
                  }
                },
                :dataDisks => [
                  {
                    :name => "l",
                    :lun  => 0,
                    :createOption => "Empty",
                    :diskSizeGB => "o",
                    :vhd => {
                      :uri => "m"
                    },
                    :caching => "n"
                  }
                ]
              }
            }
          }
        }

        it "should raise no error" do
          stub_request(:post, token_uri).to_return(
            :status => 200,
            :body => {
              "access_token" => valid_access_token,
              "expires_on" => expires_on
            }.to_json,
            :headers => {})
          stub_request(:put, vm_uri).with(body: request_body).to_return(
            :status => 200,
            :body => '',
            :headers => {
              "azure-asyncoperation" => operation_status_link
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end
    end

    context "when token is invalid" do
      it "should raise an error if token is not gotten" do
        stub_request(:post, token_uri).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /get_token - http code: 404/
      end

      it "should raise an error if tenant id, client id or client secret is invalid" do
        stub_request(:post, token_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
      end

      it "should raise an error if authentication retry fails" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 401,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /Azure authentication failed: Token is invalid./
      end
    end

    context "when token expired" do
      context "when authentication retry succeeds" do
        before do
          stub_request(:post, token_uri).to_return({
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {}
            })
          stub_request(:put, vm_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            }, {
              :status => 200,
              :body => '',
              :headers => {
                "azure-asyncoperation" => operation_status_link
              }
            })
          stub_request(:get, operation_status_link).to_return(
            :status => 200,
            :body => '{"status":"Succeeded"}',
            :headers => {})
        end
        it "should not raise an error" do

          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.not_to raise_error
        end
      end

      context "when authentication retry fails" do
        before do
          stub_request(:post, token_uri).to_return({
              :status => 200,
              :body => {
                "access_token" => valid_access_token,
                "expires_on" => expires_on
              }.to_json,
              :headers => {}
            }, {
              :status => 401,
              :body => '',
              :headers => {}
            })
          stub_request(:put, vm_uri).to_return({
              :status => 401,
              :body => 'The token expired'
            })
        end

        it "should raise an error if authentication retry fails" do
          expect {
            azure_client2.create_virtual_machine(vm_params, network_interfaces)
          }.to raise_error /get_token - http code: 401. Azure authentication failed: Invalid tenant id, client id or client secret./
        end
      end
    end

    context "when another process is operating the same VM" do
      it "should raise AzureConflictError" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 409,
          :body => 'Another process is operating the same VM',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error Bosh::AzureCloud::AzureConflictError
      end
    end

    context "when network interface count exceeds the max allowed NIC number" do
      it "should raise AzureError" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 400,
          :body => 'The number of network interfaces for virtual machine xxx exceeds the maximum allowed for the virtual machine size Standard_D1.',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error /The number of network interfaces for virtual machine xxx exceeds the maximum/
      end
    end

    context "when token is valid, create operation is accepted and not completed" do
      it "should raise an error if check completion operation is not accepeted" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 404,
          :body => '',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error { |error| expect(error.error).to match(/check_completion - http code: 404/) }
      end

      it "should raise an error if create operation failed" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Cancelled"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.to raise_error { |error| expect(error.status).to eq('Cancelled') }
      end
    end

    context "when token is valid, create operation is accepted and completed" do
      it "should raise no error" do
        stub_request(:post, token_uri).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:put, vm_uri).to_return(
          :status => 200,
          :body => '',
          :headers => {
            "azure-asyncoperation" => operation_status_link
          })
        stub_request(:get, operation_status_link).to_return(
          :status => 200,
          :body => '{"status":"Succeeded"}',
          :headers => {})

        expect {
          azure_client2.create_virtual_machine(vm_params, network_interfaces)
        }.not_to raise_error
      end
    end
  end
end
