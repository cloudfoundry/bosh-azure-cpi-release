# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  let(:extra_storage_account_name) { ENV.fetch('BOSH_AZURE_EXTRA_STORAGE_ACCOUNT_NAME', nil) }

  describe '#calculate_vm_cloud_properties' do
    let(:vm_resources) do
      {
        'cpu' => 2,
        'ram' => 4096,
        'ephemeral_disk_size' => 32 * 1024
      }
    end

    it 'should return Azure specific cloud properties' do
      expect(@cpi.calculate_vm_cloud_properties(vm_resources)['instance_type']).to be_nil
      expect(@cpi.calculate_vm_cloud_properties(vm_resources)['instance_types']).not_to be_empty
      expect(@cpi.calculate_vm_cloud_properties(vm_resources)['ephemeral_disk']['size']).to eq(32 * 1024)
    end
  end

  context 'when assigning dynamic public IP to VM' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        }
      }
    end
    let(:vm_properties) do
      {
        'instance_type' => @instance_type,
        'assign_dynamic_public_ip' => true
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end

  context 'when api version 2' do
    let(:options) do
      {
        'azure' => {
          'request_id' => 'abc123',
          'director_uuid' => 'abc123',
          'environment' => @azure_environment,
          'subscription_id' => @subscription_id,
          'resource_group_name' => @default_resource_group_name,
          'tenant_id' => @tenant_id,
          'client_id' => @client_id,
          'client_secret' => @client_secret,
          'ssh_user' => 'vcap',
          'ssh_public_key' => @ssh_public_key,
          'default_security_group' => @default_security_group,
          'parallel_upload_thread_num' => 16,
          'use_managed_disks' => true,
          'vm' => {
            'stemcell' => {
              'api_version' => 2
            }
          }
        }
      }
    end
    let(:vm_properties) do
      {
        'instance_type' => @instance_type,
      }
    end
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        }
      }
    end

    context 'when attaching disk' do
      it 'returns disk hints' do
        cpi = Bosh::AzureCloud::Cloud.new(options, 2)

        vm_lifecycle(stemcell_id: @stemcell_id, cpi: cpi) do |instance_id|
          disk = cpi.create_disk(1024, {})
          result = cpi.attach_disk(instance_id, disk)
          expect(result).not_to be_nil
          expect(result).to be_a(Hash)
          expect(result.keys).to eq(%w[lun host_device_id])
        end
      end
    end
  end
end
