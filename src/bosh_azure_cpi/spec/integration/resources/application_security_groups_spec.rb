# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @application_security_group = ENV.fetch('BOSH_AZURE_APPLICATION_SECURITY_GROUP')
  end

  context 'when assigning application security groups to VM NIC', application_security_group: true do
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
        'application_security_groups' => [@application_security_group]
      }
    end

    it 'should exercise the vm lifecycle' do
      vm_lifecycle do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
        network_interface = get_azure_client.get_network_interface_by_name(@default_resource_group_name, "#{instance_id_obj.vm_name}-0")
        asgs = network_interface[:application_security_groups]
        asg_names = []
        asgs.each do |asg|
          asg_names.push(asg[:name])
        end
        expect(asg_names).to eq([@application_security_group])
      end
    end
  end
end
