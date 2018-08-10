# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  context 'dynamic networking' do
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
        }
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle
    end
  end
end
