# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @primary_public_ip  = ENV.fetch('BOSH_AZURE_PRIMARY_PUBLIC_IP')
    @second_subnet_name = ENV.fetch('BOSH_AZURE_SECOND_SUBNET_NAME')
  end

  context 'multiple nics' do
    let(:vm_properties) do
      {
        'instance_type' => 'Standard_D2_v2'
      }
    end
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'dynamic',
          'default' => %w[dns gateway],
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        },
        'network_b' => {
          'type' => 'manual',
          'ip' => "10.0.1.#{Random.rand(10..99)}",
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @second_subnet_name
          }
        },
        'network_c' => {
          'type' => 'vip',
          'ip' => @primary_public_ip
        }
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end
end
