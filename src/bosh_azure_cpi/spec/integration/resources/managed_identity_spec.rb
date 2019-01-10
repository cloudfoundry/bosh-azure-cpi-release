# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @default_user_assigned_identity_name = ENV.fetch('BOSH_AZURE_DEFAULT_USER_ASSIGNED_IDENTITY_NAME')
    @user_assigned_identity_name         = ENV.fetch('BOSH_AZURE_USER_ASSIGNED_IDENTITY_NAME')
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

  context 'when default_managed_identity is not specified in global configurations' do
    context 'when managed_identity is specified in vm_extensions' do
      let(:vm_properties) do
        {
          'instance_type' => @instance_type,
          'managed_identity' => {
            'type' => 'UserAssigned',
            'user_assigned_identity_name' => @user_assigned_identity_name
          }
        }
      end

      it 'should exercise the vm lifecycle with the managed identity' do
        vm_lifecycle do |instance_id|
          instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
          vm = @cpi.azure_client.get_virtual_machine_by_name(@default_resource_group_name, instance_id_obj.vm_name.to_s)
          expect(vm[:identity][:type]).to eq('UserAssigned')
          expect(vm[:identity][:identity_ids][0]).to include(@user_assigned_identity_name)
        end
      end
    end
  end

  context 'when default_managed_identity is specified' do
    subject(:cpi_with_default_managed_identity) do
      cloud_options_with_default_managed_identity = @cloud_options.dup
      cloud_options_with_default_managed_identity['azure']['default_managed_identity'] = {
        'type' => 'UserAssigned',
        'user_assigned_identity_name' => @default_user_assigned_identity_name
      }
      described_class.new(cloud_options_with_default_managed_identity, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
    end

    context 'when managed_identity is specified in vm_extensions' do
      let(:vm_properties) do
        {
          'instance_type' => @instance_type,
          'managed_identity' => {
            'type' => 'UserAssigned',
            'user_assigned_identity_name' => @user_assigned_identity_name
          }
        }
      end

      it 'should exercise the vm lifecycle with the managed identity' do
        vm_lifecycle(cpi: cpi_with_default_managed_identity) do |instance_id|
          instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
          vm = @cpi.azure_client.get_virtual_machine_by_name(@default_resource_group_name, instance_id_obj.vm_name.to_s)
          expect(vm[:identity][:type]).to eq('UserAssigned')
          expect(vm[:identity][:identity_ids][0]).to include(@user_assigned_identity_name)
        end
      end
    end

    context 'when managed_identity is not specified in vm_extensions' do
      let(:vm_properties) do
        {
          'instance_type' => @instance_type
        }
      end

      it 'should exercise the vm lifecycle with the default managed identity' do
        vm_lifecycle(cpi: cpi_with_default_managed_identity) do |instance_id|
          instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
          vm = @cpi.azure_client.get_virtual_machine_by_name(@default_resource_group_name, instance_id_obj.vm_name.to_s)
          expect(vm[:identity][:type]).to eq('UserAssigned')
          expect(vm[:identity][:identity_ids][0]).to include(@default_user_assigned_identity_name)
        end
      end
    end
  end
end
