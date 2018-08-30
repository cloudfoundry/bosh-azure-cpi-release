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

  let(:disk_name) { 'fake-disk-name' }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#create_empty_managed_disk' do
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    context 'when common disk_params are provided' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          disk_size: 'c',
          account_type: 'd'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          sku: {
            name: 'd'
          },
          properties: {
            creationData: {
              createOption: 'Empty'
            },
            diskSizeGB: 'c'
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_empty_managed_disk(resource_group, disk_params)
        end.not_to raise_error
      end
    end

    context 'when zone is specified' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          disk_size: 'c',
          account_type: 'd',
          zone: 'e'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          zones: ['e'],
          sku: {
            name: 'd'
          },
          properties: {
            creationData: {
              createOption: 'Empty'
            },
            diskSizeGB: 'c'
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_empty_managed_disk(resource_group, disk_params)
        end.not_to raise_error
      end
    end
  end

  describe '#create_managed_disk_from_blob' do
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    context 'when common disk_params are provided' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          source_uri: 'c',
          account_type: 'd'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          sku: {
            name: 'd'
          },
          properties: {
            creationData: {
              createOption: 'Import',
              sourceUri: 'c'
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_managed_disk_from_blob(resource_group, disk_params)
        end.not_to raise_error
      end
    end

    context 'when zone is specified' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          source_uri: 'c',
          account_type: 'd',
          zone: 'e'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          zones: ['e'],
          sku: {
            name: 'd'
          },
          properties: {
            creationData: {
              createOption: 'Import',
              sourceUri: 'c'
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_managed_disk_from_blob(resource_group, disk_params)
        end.not_to raise_error
      end
    end
  end

  describe '#create_managed_disk_from_snapshot' do
    let(:snapshot_name) { 'fake-snapshot-name' }
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }
    let(:snapshot_url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/snapshots/#{snapshot_name}" }

    context 'when common disk_params are provided' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          account_type: 'c'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          sku: {
            name: 'c'
          },
          properties: {
            creationData: {
              createOption: 'Copy',
              sourceResourceId: snapshot_url
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_managed_disk_from_snapshot(resource_group, disk_params, snapshot_name)
        end.not_to raise_error
      end
    end

    context 'when zone is specified' do
      let(:disk_params) do
        {
          name: disk_name,
          location: 'b',
          tags: { 'foo' => 'bar' },
          account_type: 'c',
          zone: 'd'
        }
      end

      let(:request_body) do
        {
          location: 'b',
          tags: {
            foo: 'bar'
          },
          zones: ['d'],
          sku: {
            name: 'c'
          },
          properties: {
            creationData: {
              createOption: 'Copy',
              sourceResourceId: snapshot_url
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
        stub_request(:put, disk_uri).with(body: request_body).to_return(
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
          azure_client.create_managed_disk_from_snapshot(resource_group, disk_params, snapshot_name)
        end.not_to raise_error
      end
    end
  end

  describe '#get_managed_disk_by_name' do
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    let(:response_body) do
      {
        id: 'a',
        name: 'b',
        location: 'c',
        tags: {
          foo: 'bar'
        },
        sku: {
          name: 'f',
          tier: 'g'
        },
        zones: ['fake-zone'],
        properties: {
          provisioningState: 'd',
          diskSizeGB: 'e'
        }
      }
    end
    let(:disk) do
      {
        id: 'a',
        name: 'b',
        location: 'c',
        tags: {
          'foo' => 'bar'
        },
        sku_name: 'f',
        sku_tier: 'g',
        zone: 'fake-zone',
        provisioning_state: 'd',
        disk_size: 'e'
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
      stub_request(:get, disk_uri).to_return(
        status: 200,
        body: response_body.to_json,
        headers: {}
      )

      expect(
        azure_client.get_managed_disk_by_name(resource_group, disk_name)
      ).to eq(disk)
    end
  end

  describe '#delete_managed_disk' do
    let(:disk_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/disks/#{disk_name}?api-version=#{api_version_compute}" }

    context 'when token is valid, delete operation is accepted and completed' do
      it 'should delete the managed disk without error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, disk_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )

        expect do
          azure_client.delete_managed_disk(resource_group, disk_name)
        end.not_to raise_error
      end
    end
    context 'when retry reach max number.' do
      it 'should raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, disk_uri).to_return(
          status: 202,
          body: '{}',
          headers: {
            'azure-asyncoperation' => operation_status_link
          }
        )
        eleven_failed = []
        11.times do
          eleven_failed.push(
            status: 200,
            body: '{"status":"Failed"}',
            headers: {
              'Retry-After' => '1'
            }
          )
        end
        stub_request(:get, operation_status_link).to_return(
          eleven_failed
        )
        expect do
          azure_client.delete_managed_disk(resource_group, disk_name)
        end.to raise_error /check_completion - http code: 200/
      end
    end
  end
end
