# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::VMCloudProps do
  include_context 'shared stuff'

  describe '#initialize' do
    context 'when instance_type and instance_types are not provided' do
      let(:vm_cloud_properties) { {} }

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config_managed)
        end.to raise_error('You need to specify one of \'vm_type/instance_type\' or \'vm_resources\'.')
      end
    end

    context 'when availability_set is a hash' do
      let(:av_set_name) { 'fake_av_set_name' }
      let(:platform_update_domain_count) { 5 }
      let(:platform_fault_domain_count) { 1 }
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'availability_set' => {
              'name' => av_set_name,
              'platform_update_domain_count' => platform_update_domain_count,
              'platform_fault_domain_count' => platform_fault_domain_count
            },
            'platform_update_domain_count' => 4,
            'platform_fault_domain_count' => 1
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.availability_set.name).to eq(av_set_name)
        expect(vm_cloud_props.availability_set.platform_update_domain_count).to eq(platform_update_domain_count)
        expect(vm_cloud_props.availability_set.platform_fault_domain_count).to eq(platform_fault_domain_count)
      end
    end

    context 'when availability_zone is specified' do
      let(:vm_cloud_properties) do
        {
          'availability_zone' => 'fake-az',
          'instance_type' => 'fake-vm-size'
        }
      end

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config)
        end.to raise_error('Virtual Machines deployed to an Availability Zone must use managed disks')
      end
    end

    context 'when an invalid availability_zone is specified' do
      let(:zone) { 'invalid-zone' } # valid values are '1', '2', '3'
      let(:vm_cloud_properties) do
        {
          'availability_zone' => zone,
          'instance_type' => 'c'
        }
      end

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config_managed)
        end.to raise_error /'#{zone}' is not a valid zone/
      end
    end

    context 'when both availability_zone and availability_set are specified' do
      let(:vm_cloud_properties) do
        {
          'availability_zone' => '1',
          'availability_set' => 'b',
          'instance_type' => 'c'
        }
      end

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config_managed)
        end.to raise_error /Only one of 'availability_zone' and 'availability_set' is allowed to be configured for the VM but you have configured both/
      end
    end

    context 'when load_balancer is a hash' do
      let(:lb_name) { 'fake_lb_name' }
      let(:resource_group_name) { 'fake_resource_group' }
      context 'when resource group not empty' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'load_balancer' => {
                'name' => lb_name,
                'resource_group_name' => resource_group_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.load_balancer.name).to eq(lb_name)
          expect(vm_cloud_props.load_balancer.resource_group_name).to eq(resource_group_name)
        end
      end

      context 'when resource group empty' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'load_balancer' => {
                'name' => lb_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.load_balancer.name).to eq(lb_name)
          expect(vm_cloud_props.load_balancer.resource_group_name).to eq(azure_config_managed.resource_group_name)
        end
      end
    end

    context '#managed_identity' do
      context 'when default_managed_identity is not specified in global configurations' do
        context 'when managed_identity is not specified in vm_extensions' do
          let(:vm_cloud_props) do
            Bosh::AzureCloud::VMCloudProps.new(
              {
                'instance_type' => 'Standard_D1'
              }, azure_config_managed
            )
          end

          it 'should return nil' do
            expect(vm_cloud_props.managed_identity).to be_nil
          end
        end

        context 'when managed_identity is specified in vm_extensions' do
          let(:vm_cloud_props) do
            Bosh::AzureCloud::VMCloudProps.new(
              {
                'instance_type' => 'Standard_D1',
                'managed_identity' => {
                  'type' => 'SystemAssigned'
                }
              }, azure_config_managed
            )
          end

          it 'should return managed identity' do
            expect(vm_cloud_props.managed_identity).not_to be_nil
          end
        end
      end

      context 'when default_managed_identity is specified in global configurations' do
        let(:azure_config) do
          mock_azure_config_merge(
            'default_managed_identity' => {
              'type' => 'SystemAssigned'
            }
          )
        end

        context 'when managed_identity is not specified in vm_extensions' do
          let(:vm_cloud_props) do
            Bosh::AzureCloud::VMCloudProps.new(
              {
                'instance_type' => 'Standard_D1'
              }, azure_config
            )
          end

          it 'should return default_managed_identity' do
            expect(vm_cloud_props.managed_identity.type).to eq('SystemAssigned')
          end
        end

        context 'when managed_identity is specified in vm_extensions' do
          let(:vm_cloud_props) do
            Bosh::AzureCloud::VMCloudProps.new(
              {
                'instance_type' => 'Standard_D1',
                'managed_identity' => {
                  'type' => 'UserAssigned',
                  'user_assigned_identity_name' => 'fake-identity-name'
                }
              }, azure_config
            )
          end

          it 'should return managed_identity' do
            expect(vm_cloud_props.managed_identity.type).to eq('UserAssigned')
            expect(vm_cloud_props.managed_identity.user_assigned_identity_name).to eq('fake-identity-name')
          end
        end
      end
    end
  end
end
