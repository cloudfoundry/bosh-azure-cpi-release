# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  let(:vm_name) { 'fake-vm-name' }
  let(:tags) { {} }

  before do
    allow(azure_client).to receive(:sleep)
  end

  describe '#attach_disk_to_virtual_machine' do
    let(:disk_name) { 'fake-disk-name' }
    let(:caching) { 'ReadWrite' }
    let(:vm_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines/#{vm_name}?api-version=#{api_version_compute}" }
    let(:disk_bosh_id) { 'fake-bosh-id' }

    context 'when attaching a managed disk' do
      let(:disk_params) do
        {
          disk_name: disk_name,
          caching: caching,
          disk_id: disk_id,
          managed: true,
          disk_bosh_id: disk_bosh_id
        }
      end
      let(:response_body) do
        {
          'id' => 'fake-id',
          'name' => 'fake-name',
          'location' => 'fake-location',
          'tags' => {},
          'properties' => {
            'provisioningState' => 'fake-state',
            'storageProfile' => {
              'dataDisks' => [
                { 'lun' => 0 },
                { 'lun' => 1 }
              ]
            },
            'hardwareProfile' => {
              'vmSize' => 'Standard_A5'
            }
          }
        }.to_json
      end
      let(:lun) { 2 }
      let(:request_body) do
        {
          'id' => 'fake-id',
          'name' => 'fake-name',
          'location' => 'fake-location',
          'tags' => {
            "disk-id-#{disk_name}" => disk_bosh_id
          },
          'properties' => {
            'provisioningState' => 'fake-state',
            'storageProfile' => {
              'dataDisks' => [
                { 'lun' => 0 },
                { 'lun' => 1 },
                {
                  'name' => disk_name,
                  'lun' => lun,
                  'createOption' => 'Attach',
                  'caching' => caching,
                  'managedDisk' => { 'id' => disk_id }
                }
              ]
            },
            'hardwareProfile' => {
              'vmSize' => 'Standard_A5'
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
        stub_request(:get, vm_uri).to_return(
          status: 200,
          body: response_body,
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

        expect(
          azure_client.attach_disk_to_virtual_machine(resource_group, vm_name, disk_params)
        ).to eq(lun)
      end
    end

    context 'when attaching an unmanaged disk' do
      let(:disk_uri) { 'fake-disk-uri' }
      let(:disk_size) { 42 }
      let(:disk_params) do
        {
          disk_name: disk_name,
          caching: caching,
          disk_uri: disk_uri,
          disk_size: disk_size,
          managed: false,
          disk_bosh_id: disk_bosh_id
        }
      end
      let(:lun) { 2 }
      let(:request_body) do
        {
          'id' => 'fake-id',
          'name' => 'fake-name',
          'location' => 'fake-location',
          'tags' => {
            "disk-id-#{disk_name}" => disk_bosh_id
          },
          'properties' => {
            'provisioningState' => 'fake-state',
            'storageProfile' => {
              'dataDisks' => [
                { 'lun' => 0 },
                { 'lun' => 1 },
                {
                  'name' => disk_name,
                  'lun' => lun,
                  'createOption' => 'Attach',
                  'caching' => caching,
                  'diskSizeGb' => disk_size,
                  'vhd' => { 'uri' => disk_uri }
                }
              ]
            },
            'hardwareProfile' => {
              'vmSize' => 'Standard_A5'
            }
          }
        }
      end

      context "when VM's information does not contain 'resources'" do
        let(:response_body) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => {},
            'properties' => {
              'provisioningState' => 'fake-state',
              'storageProfile' => {
                'dataDisks' => [
                  { 'lun' => 0 },
                  { 'lun' => 1 }
                ]
              },
              'hardwareProfile' => {
                'vmSize' => 'Standard_A5'
              }
            }
          }.to_json
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
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: response_body,
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

          expect(
            azure_client.attach_disk_to_virtual_machine(resource_group, vm_name, disk_params)
          ).to eq(2)
        end
      end

      context "when VM's information contains 'resources'" do
        let(:response_body) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => {},
            'properties' => {
              'provisioningState' => 'fake-state',
              'storageProfile' => {
                'dataDisks' => [
                  { 'lun' => 0 },
                  { 'lun' => 1 }
                ]
              },
              'hardwareProfile' => {
                'vmSize' => 'Standard_A5'
              }
            },
            'resources' => [
              {
                "properties": {},
                "id": 'fake-id',
                "name": 'fake-name',
                "type": 'fake-type',
                "location": 'fake-location'
              }
            ]
          }.to_json
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
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: response_body,
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

          expect(
            azure_client.attach_disk_to_virtual_machine(resource_group, vm_name, disk_params)
          ).to eq(2)
        end
      end

      context 'when the virtual machine is not found' do
        it 'should raise an error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: '',
            headers: {}
          )

          expect do
            azure_client.attach_disk_to_virtual_machine(resource_group, vm_name, disk_params)
          end.to raise_error /attach_disk_to_virtual_machine - cannot find the virtual machine by name/
        end
      end

      context 'when no avaiable lun can be found' do
        let(:response_body) do
          {
            'id' => 'fake-id',
            'name' => 'fake-name',
            'location' => 'fake-location',
            'tags' => {},
            'properties' => {
              'provisioningState' => 'fake-state',
              'storageProfile' => {
                'dataDisks' => [
                  { 'lun' => 0 },
                  { 'lun' => 1 }
                ]
              },
              'hardwareProfile' => {
                'vmSize' => 'Standard_A1' # Standard_A1 only has 2 available luns
              }
            }
          }.to_json
        end

        it 'should raise an error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vm_uri).to_return(
            status: 200,
            body: response_body,
            headers: {}
          )

          expect do
            azure_client.attach_disk_to_virtual_machine(resource_group, vm_name, disk_params)
          end.to raise_error /attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine/
        end
      end
    end
  end
end
