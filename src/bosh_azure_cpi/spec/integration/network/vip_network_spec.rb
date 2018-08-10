# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @primary_public_ip = ENV.fetch('BOSH_AZURE_PRIMARY_PUBLIC_IP')
  end

  context 'vip networking' do
    let(:vm_properties) do
      {
        'instance_type' => @instance_type
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
        },
        'network_b' => {
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
