# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  let(:extra_storage_account_name) { ENV.fetch('BOSH_AZURE_EXTRA_STORAGE_ACCOUNT_NAME', nil) }

  context '#calculate_vm_cloud_properties' do
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

  context 'when assigning a different storage account to VM', unmanaged_disks: true do
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
        'storage_account_name' => extra_storage_account_name
      }
    end

    it 'should exercise the vm lifecycle' do
      lifecycles = []
      3.times do |i|
        lifecycles[i] = Thread.new do
          vm_lifecycle
        end
      end
      lifecycles.each(&:join)
    end
  end
end
