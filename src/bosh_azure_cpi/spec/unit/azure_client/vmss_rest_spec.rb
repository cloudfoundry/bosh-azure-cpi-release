# frozen_string_literal: true

require 'spec_helper'
require 'unit/azure_client/shared_stuff.rb'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  include_context 'shared stuff for azure client'

  describe '#get_vmss_by_name' do
    context 'when everything ok' do
      let(:vmss_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}?api-version=#{api_version_compute}" }
      let(:vmss_result) do
        {
          sku: {
            name: 'Standard_A1_v2',
            capacity: 1
          }
        }
      end
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, vmss_uri).to_return(
          status: 200,
          body: vmss_result.to_json,
          headers: {}
        )
        expect do
          azure_client.get_vmss_by_name(resource_group, vmss_name)
        end.not_to raise_error
      end
    end
  end

  describe '#get_vmss_instances' do
    context 'when everything ok' do
      let(:vmss_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines?api-version=#{api_version_compute}" }
      let(:vmss_instances_result) do
        {
          value: [
            {
              instanceId: vmss_instance_id,
              name: "#{vmss_name}_#{vmss_instance_id}"
            }
          ]
        }
      end
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, vmss_uri).to_return(
          status: 200,
          body: vmss_instances_result.to_json,
          headers: {}
        )
        expect do
          azure_client.get_vmss_instances(resource_group, vmss_name)
        end.not_to raise_error
      end
    end
  end

  describe '#get_vmss_instance' do
    context 'when os disk is managed disk' do
      let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}?api-version=#{api_version_compute}" }
      let(:fake_nic_id) { 'nic_1' }
      let(:nic_instance_uri) { "https://management.azure.com/#{fake_nic_id}?api-version=#{group_api_version}" }
      let(:vmss_instance_result) do
        {
          properties: {
            storageProfile: {
              osDisk: {
                managedDisk: {

                }
              },
              dataDisks: [
                {
                  managedDisk: {

                  }
                }
              ]
            },
            networkProfile: {
              networkInterfaces: [
                {
                  id: 'nic_1'
                }
              ]
            }
          },
          sku: {
            name: 'Standard_A5'
          }
        }
      end
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, nic_instance_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        stub_request(:get, vmss_instance_uri).to_return(
          status: 200,
          body: vmss_instance_result.to_json,
          headers: {}
        )
        expect do
          azure_client.get_vmss_instance(resource_group, vmss_name, vmss_instance_id)
        end.not_to raise_error
      end
    end
  end

  describe '#create_vmss' do
    let(:vm_params) do
      {
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
        load_balancer: {
          backend_address_pools: [{
            id: 'p'
          }]
        }
      }
    end

    let(:vm_params_windows) do
      vm_params_windows = vm_params.dup
      vm_params_windows[:os_type] = 'windows'
      vm_params_windows
    end

    let(:vm_params_bsd) do
      vm_params_bsd = vm_params.dup
      vm_params_bsd[:os_type] = 'bsd'
      vm_params_bsd
    end

    let(:network_interfaces) do
      [
        {
          subnet: {
            id: 'q'
          },
          network_security_group: {
            id: 'r'
          }
        }
      ]
    end
    context 'when everything ok' do
      let(:vmss_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets?api-version=#{api_version_compute}&validating=true" }
      let(:create_vmss_request_body) do
        {}
      end
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:put, vmss_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        expect do
          azure_client.create_vmss(resource_group, vm_params, network_interfaces)
        end.not_to raise_error
      end
    end
    context 'when windows os' do
      it 'should raise error' do
        expect do
          azure_client.create_vmss(resource_group, vm_params_windows, network_interfaces)
        end.to raise_error /Unsupported os type/
      end
    end
    context 'when other os' do
      it 'should raise error' do
        expect do
          azure_client.create_vmss(resource_group, vm_params_bsd, network_interfaces)
        end.to raise_error /Unsupported os type/
      end
    end
  end

  describe '#scale_vmss_up' do
    context 'when everything ok' do
      let(:number) { 1 }
      let(:vmss_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}?api-version=#{api_version_compute}" }
      let(:vmss_uri_put) { "#{vmss_uri}&validating=true" }
      let(:vmss_result) do
        {
          sku: {
            capacity: 1
          }
        }
      end
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, vmss_uri).to_return(
          status: 200,
          body: vmss_result.to_json,
          headers: {}
        )
        stub_request(:put, vmss_uri_put).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        expect do
          azure_client.scale_vmss_up(resource_group, vmss_name, number)
        end.not_to raise_error
      end
    end
  end

  describe '#attach_disk_to_vmss_instance' do
    let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}?api-version=#{api_version_compute}" }
    let(:vmss_instance_uri_put) { "#{vmss_instance_uri}&validating=true" }
    let(:vmss_instance_result) do
      {
        properties: {
          storageProfile: {
            dataDisks: [
              { lun: 0 }
            ]
          }
        },
        sku: {
          name: 'Standard_A5'
        }
      }
    end

    let(:caching) { 'ReadWrite' }
    let(:disk_params) do
      {
        caching: caching,
        disk_id: disk_id
      }
    end
    it 'should not raise error' do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
      stub_request(:get, vmss_instance_uri).to_return(
        status: 200,
        body: vmss_instance_result.to_json,
        headers: {}
      )
      stub_request(:put, vmss_instance_uri_put).to_return(
        status: 200,
        body: '',
        headers: {}
      )
      expect do
        azure_client.attach_disk_to_vmss_instance(resource_group, vmss_name, vmss_instance_id, disk_params)
      end.not_to raise_error
    end
  end

  describe '#detach_disk_from_vmss_instance' do
    let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}?api-version=#{api_version_compute}" }
    let(:vmss_instance_uri_put) { "#{vmss_instance_uri}&validating=true" }
    let(:vmss_instance_result) do
      {
        properties: {
          storageProfile: {
            dataDisks: [
              {
                managedDisk: {
                  id: disk_id
                }
              }
            ]
          },
          hardwareProfile: {
            vmSize: 'Standard_A5'
          }
        }
      }
    end
    it 'should not raise error' do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
      stub_request(:get, vmss_instance_uri).to_return(
        status: 200,
        body: vmss_instance_result.to_json,
        headers: {}
      )
      stub_request(:put, vmss_instance_uri_put).to_return(
        status: 200,
        body: '',
        headers: {}
      )
      expect do
        azure_client.detach_disk_from_vmss_instance(resource_group, vmss_name, vmss_instance_id, disk_id)
      end.not_to raise_error
    end
  end

  describe '#reboot_vmss_instance' do
    context 'when everything ok' do
      let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}/restart?api-version=#{api_version_compute}" }
      let(:vmss_instance_uri_post) { "#{vmss_instance_uri}&validating=true" }
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:post, vmss_instance_uri_post).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        expect do
          azure_client.reboot_vmss_instance(resource_group, vmss_name, vmss_instance_id)
        end.not_to raise_error
      end
    end
  end

  describe '#delete_vmss_instance' do
    context 'when everything ok' do
      let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}?api-version=#{api_version_compute}&validating=true" }
      it 'should not raise error' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:delete, vmss_instance_uri).to_return(
          status: 200,
          body: '',
          headers: {}
        )
        expect do
          azure_client.delete_vmss_instance(resource_group, vmss_name, vmss_instance_id)
        end.not_to raise_error
      end
    end
  end

  describe '#set_vmss_instance_metadata' do
    context 'when everything ok' do
      let(:vmss_name) { 'fake_vmss_name' }
      let(:vmss_instance_id) { '0' }
      let(:tags) { {} }
      let(:vmss_instance_result) do
        {
          tags: {}
        }
      end
      let(:vmss_instance_without_tags) do
        {}
      end
      let(:vmss_instance_uri) { "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/#{vmss_name}/virtualMachines/#{vmss_instance_id}?api-version=#{api_version_compute}" }
      let(:vmss_instance_uri_put) { "#{vmss_instance_uri}&validating=true" }
      context 'when tags existing' do
        it 'should not raise error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vmss_instance_uri).to_return(
            status: 200,
            body: vmss_instance_result.to_json,
            headers: {}
          )
          stub_request(:put, vmss_instance_uri_put).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect do
            azure_client.set_vmss_instance_metadata(resource_group, vmss_name, vmss_instance_id, tags)
          end.not_to raise_error
        end
      end
      context 'when tags not exists' do
        it 'should not raise error' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, vmss_instance_uri).to_return(
            status: 200,
            body: vmss_instance_without_tags.to_json,
            headers: {}
          )
          stub_request(:put, vmss_instance_uri_put).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect do
            azure_client.set_vmss_instance_metadata(resource_group, vmss_name, vmss_instance_id, tags)
          end.not_to raise_error
        end
      end
    end
  end
end
