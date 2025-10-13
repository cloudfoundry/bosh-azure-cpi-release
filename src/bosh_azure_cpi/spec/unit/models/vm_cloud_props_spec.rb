# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

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
        end.to raise_error(/'#{zone}' is not a valid zone/)
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
        end.to raise_error(/Only one of 'availability_zone' and 'availability_set' is allowed to be configured for the VM but you have configured both/)
      end
    end

    context 'when load_balancer is not specified' do
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1'
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.load_balancers).to be_nil
      end
    end

    context 'when load_balancer is a string' do
      let(:lb_name) { 'fake_lb_name' }

      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'load_balancer' => lb_name
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.load_balancers.length).to eq(1)
        load_balancer = vm_cloud_props.load_balancers.first
        expect(load_balancer.name).to eq(lb_name)
        expect(load_balancer.resource_group_name).to eq(azure_config_managed.resource_group_name)
      end
    end

    context 'when load_balancer is a comma-delimited string' do
      let(:lb_name) { 'fake_lb_name' }

      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'load_balancer' => "#{lb_name},b,c"
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.load_balancers.length).to eq(3)
        expect(vm_cloud_props.load_balancers[0].name).to eq(lb_name)
        expect(vm_cloud_props.load_balancers[0].resource_group_name).to eq(azure_config_managed.resource_group_name)
        expect(vm_cloud_props.load_balancers[1].name).to eq('b')
        expect(vm_cloud_props.load_balancers[1].resource_group_name).to eq(azure_config_managed.resource_group_name)
        expect(vm_cloud_props.load_balancers[2].name).to eq('c')
        expect(vm_cloud_props.load_balancers[2].resource_group_name).to eq(azure_config_managed.resource_group_name)
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
          expect(vm_cloud_props.load_balancers.length).to eq(1)
          load_balancer = vm_cloud_props.load_balancers.first
          expect(load_balancer.name).to eq(lb_name)
          expect(load_balancer.resource_group_name).to eq(resource_group_name)
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
          expect(vm_cloud_props.load_balancers.length).to eq(1)
          load_balancer = vm_cloud_props.load_balancers.first
          expect(load_balancer.name).to eq(lb_name)
          expect(load_balancer.resource_group_name).to eq(azure_config_managed.resource_group_name)
        end
      end

      context 'when name is a comma-delimited string' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'load_balancer' => {
                'name' => "#{lb_name},b,c",
                'resource_group_name' => resource_group_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.load_balancers.length).to eq(3)
          expect(vm_cloud_props.load_balancers[0].name).to eq(lb_name)
          expect(vm_cloud_props.load_balancers[0].resource_group_name).to eq(resource_group_name)
          expect(vm_cloud_props.load_balancers[1].name).to eq('b')
          expect(vm_cloud_props.load_balancers[1].resource_group_name).to eq(resource_group_name)
          expect(vm_cloud_props.load_balancers[2].name).to eq('c')
          expect(vm_cloud_props.load_balancers[2].resource_group_name).to eq(resource_group_name)
        end
      end
    end

    context 'when load_balancer is an array' do
      let(:resource_group_name) { 'fake_resource_group' }

      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'load_balancer' => [
              'fake_lb1_name', # String
              {
                'name' => 'fake_lb2_name'
              }, # Hash without resource_group_name
              'fake_lb3_name,fake_lb4_name', # delimited String
              {
                'name' => 'fake_lb5_name,fake_lb6_name',
                'resource_group_name' => resource_group_name
              } # Hash with delimited String and explicit resource_group_name
            ]
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        load_balancers = vm_cloud_props.load_balancers
        expect(load_balancers.length).to eq(6)

        expect(load_balancers[0].name).to eq('fake_lb1_name')
        expect(load_balancers[0].resource_group_name).to eq(azure_config_managed.resource_group_name)

        expect(load_balancers[1].name).to eq('fake_lb2_name')
        expect(load_balancers[1].resource_group_name).to eq(azure_config_managed.resource_group_name)

        expect(load_balancers[2].name).to eq('fake_lb3_name')
        expect(load_balancers[2].resource_group_name).to eq(azure_config_managed.resource_group_name)

        expect(load_balancers[3].name).to eq('fake_lb4_name')
        expect(load_balancers[3].resource_group_name).to eq(azure_config_managed.resource_group_name)

        expect(load_balancers[4].name).to eq('fake_lb5_name')
        expect(load_balancers[4].resource_group_name).to eq(resource_group_name)

        expect(load_balancers[5].name).to eq('fake_lb6_name')
        expect(load_balancers[5].resource_group_name).to eq(resource_group_name)
      end
    end

    context 'when load_balancer is an int' do
      let(:vm_cloud_properties) do
        {
          'load_balancer' => 123,
          'instance_type' => 't'
        }
      end

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config_managed)
        end.to raise_error('Property \'load_balancer\' must be a String, Hash, or Array.')
      end
    end

    context 'when application_gateway is not specified' do
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1'
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.application_gateways).to be_nil
      end
    end

    context 'when application_gateway is a string' do
      let(:agw_name) { 'fake_agw_name' }

      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'application_gateway' => agw_name
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.application_gateways.length).to eq(1)
        application_gateway = vm_cloud_props.application_gateways.first
        expect(application_gateway.name).to eq(agw_name)
        expect(application_gateway.resource_group_name).to be_nil
      end
    end

    context 'when application_gateway is a hash' do
      let(:agw_name) { 'fake_agw_name' }

      context 'when resource group not empty' do
        let(:resource_group_name) { 'fake_resource_group' }
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'application_gateway' => {
                'name' => agw_name,
                'resource_group_name' => resource_group_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.application_gateways.length).to eq(1)
          application_gateway = vm_cloud_props.application_gateways.first
          expect(application_gateway.name).to eq(agw_name)
          expect(application_gateway.resource_group_name).to eq(resource_group_name)
        end
      end

      context 'when resource group empty' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'application_gateway' => { 'name' => agw_name }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.application_gateways.length).to eq(1)
          application_gateway = vm_cloud_props.application_gateways.first
          expect(application_gateway.name).to eq(agw_name)
          expect(application_gateway.resource_group_name).to be_nil
        end
      end
    end

    context 'when application_gateway is an array' do
      let(:resource_group_name) { 'fake_resource_group' }

      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'application_gateway' => [
              'fake_agw1_name', # String
              {
                'name' => 'fake_agw2_name'
              }, # Hash without resource_group_name
              'fake_agw3_name,fake_agw4_name', # delimited String
              {
                'name' => 'fake_agw5_name,fake_agw6_name',
                'resource_group_name' => resource_group_name
              } # Hash with delimited String and explicit resource_group_name
            ]
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        application_gateways = vm_cloud_props.application_gateways
        expect(application_gateways.length).to eq(6)

        expect(application_gateways[0].name).to eq('fake_agw1_name')
        expect(application_gateways[0].resource_group_name).to be_nil

        expect(application_gateways[1].name).to eq('fake_agw2_name')
        expect(application_gateways[1].resource_group_name).to be_nil

        expect(application_gateways[2].name).to eq('fake_agw3_name')
        expect(application_gateways[2].resource_group_name).to be_nil

        expect(application_gateways[3].name).to eq('fake_agw4_name')
        expect(application_gateways[3].resource_group_name).to be_nil

        expect(application_gateways[4].name).to eq('fake_agw5_name')
        expect(application_gateways[4].resource_group_name).to eq(resource_group_name)

        expect(application_gateways[5].name).to eq('fake_agw6_name')
        expect(application_gateways[5].resource_group_name).to eq(resource_group_name)
      end
    end

    context 'when application_gateway is an int' do
      let(:vm_cloud_properties) do
        {
          'application_gateway' => 123,
          'instance_type' => 't'
        }
      end

      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config_managed)
        end.to raise_error('Property \'application_gateway\' must be a String, Hash, or Array.')
      end
    end

    context 'when root_disk is specified' do
      context 'with type and placement' do
        let(:vm_cloud_properties) do
          {
            'instance_type' => 'Standard_D1',
            'root_disk' => {
              'type' => 'Premium_ZRS',
              'placement' => 'resource-disk'
            }
          }
        end

        it 'should raise an error' do
          expect do
            Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config)
          end.to raise_error("Only one of 'type' and 'placement' is allowed to be configured for the root_disk when 'placement' is not set to persistent")
        end
      end

      context 'with type wrong placement' do
        let(:vm_cloud_properties) do
          {
            'instance_type' => 'Standard_D1',
            'root_disk' => {
              'placement' => 'local-persistent'
            }
          }
        end

        it 'should raise an error' do
          expect do
            Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, azure_config)
          end.to raise_error("root_disk 'placement' must be one of 'resource-disk','cache-disk','remote'")
        end
      end

      context 'with placement' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'root_disk' => {
                'placement' => 'cache-disk'
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          root_disk = vm_cloud_props.root_disk
          expect(root_disk.size).to be_nil
          expect(root_disk.type).to be_nil
          expect(root_disk.placement).to eq('cache-disk')
        end
      end

      context 'with disk_encryption_set_name' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'root_disk' => {
                'disk_encryption_set_name' => 'set_name'
              }
            }, azure_config_managed
          )
        end

        it 'captures the config correctly' do
          root_disk = vm_cloud_props.root_disk
          expect(root_disk.disk_encryption_set_name).to eq('set_name')
        end
      end
    end

    context 'when ephemeral disk is specified' do
      context 'with disk_encryption_set_name' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'ephemeral_disk' => {
                'disk_encryption_set_name' => 'set_name'
              }
            }, azure_config_managed
          )
        end

        it 'captures the config correctly' do
          ephemeral_disk = vm_cloud_props.ephemeral_disk
          expect(ephemeral_disk.disk_encryption_set_name).to eq('set_name')
        end
      end
    end

    describe '#managed_identity' do
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

    context 'when capacity_reservation_group is specified' do
      let(:crg_name) { 'fake-crg-name' }
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'capacity_reservation_group' => crg_name
          }, azure_config_managed
        )
      end

      it 'captures the config correctly' do
        expect(vm_cloud_props.capacity_reservation_group).to eq(crg_name)
      end
    end

    context 'when capacity_reservation_group_id is specified' do
      let(:crg_id) { '/subscriptions/969EC6E3-7F6B-4CC6-99D1-4F3913CBB6E8/resourceGroups/fake-rg-name/providers/Microsoft.Compute/capacityReservationGroups/fake-crg-name' }
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'capacity_reservation_group_id' => crg_id
          }, azure_config_managed
        )
      end

      it 'captures the config correctly' do
        expect(vm_cloud_props.capacity_reservation_group_id).to eq(crg_id)
      end
    end

     context 'when capacity_reservation_group and capacity_reservation_group_id is not specified' do
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1'
          }, azure_config_managed
        )
      end

      it 'should be nil' do
        expect(vm_cloud_props.capacity_reservation_group).to be_nil
        expect(vm_cloud_props.capacity_reservation_group_id).to be_nil
      end
    end

  end
end
