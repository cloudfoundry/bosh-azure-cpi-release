# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @default_security_group = ENV.fetch('BOSH_AZURE_DEFAULT_SECURITY_GROUP')
  end

  subject(:cpi_with_default_nsg) do
    cloud_options_with_default_nsg = @cloud_options.dup
    cloud_options_with_default_nsg['azure']['default_security_group'] = @default_security_group
    described_class.new(cloud_options_with_default_nsg, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  context 'when default_security_group is specified' do
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
      vm_lifecycle(cpi: cpi_with_default_nsg) do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
        network_interface = cpi_with_default_nsg.azure_client.get_network_interface_by_name(@default_resource_group_name, "#{instance_id_obj.vm_name}-0")
        nsg = network_interface[:network_security_group]
        expect(nsg).not_to be_nil
      end
    end
  end
end
