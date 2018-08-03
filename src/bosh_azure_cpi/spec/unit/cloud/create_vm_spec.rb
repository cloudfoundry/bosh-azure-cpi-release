# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#create_vm' do
    # Parameters
    let(:agent_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:stemcell_id) { 'bosh-stemcell-xxx' }
    let(:light_stemcell_id) { 'bosh-light-stemcell-xxx' }
    let(:vm_properties) { { 'instance_type' => 'fake-vm-size' } }
    let(:networks_spec) { {} }
    let(:disk_locality) { double('disk locality') }
    let(:environment) { double('environment') }
    let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:virtual_network_name) { 'fake-virual-network-name' }
    let(:location) { 'fake-location' }
    let(:vnet) { { location: location } }
    let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }
    let(:network) { instance_double(Bosh::AzureCloud::ManualNetwork) }
    let(:network_configurator) { double('network configurator') }

    before do
      allow(network_configurator).to receive(:networks)
        .and_return([network])
      allow(network).to receive(:resource_group_name)
        .and_return(default_resource_group_name)
      allow(network).to receive(:virtual_network_name)
        .and_return(virtual_network_name)
      allow(client2).to receive(:get_virtual_network_by_name)
        .with(default_resource_group_name, virtual_network_name)
        .and_return(vnet)
      allow(telemetry_manager).to receive(:monitor)
        .with('create_vm', id: agent_id, extras: { 'instance_type' => 'fake-vm-size' })
        .and_call_original
    end

    context 'when instance_type is not provided' do
      let(:vm_properties) { {} }

      it 'should raise an error' do
        expect do
          cloud.create_vm(
            agent_id,
            stemcell_id,
            vm_properties,
            networks_spec,
            disk_locality,
            environment
          )
        end.to raise_error(/missing required cloud property 'instance_type'./)
      end
    end

    context 'when vnet is not found' do
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config, networks_spec)
          .and_return(network_configurator)
        allow(client2).to receive(:get_virtual_network_by_name)
          .with(default_resource_group_name, virtual_network_name)
          .and_return(nil)
      end

      it 'should raise an error' do
        expect do
          cloud.create_vm(
            agent_id,
            stemcell_id,
            vm_properties,
            networks_spec,
            disk_locality,
            environment
          )
        end.to raise_error(/Cannot find the virtual network/)
      end
    end

    context 'when the location in the global configuration is different from the vnet location' do
      let(:cloud_properties_with_location) { mock_cloud_properties_merge('azure' => { 'location' => "location-other-than-#{location}" }) }
      let(:cloud_with_location) { mock_cloud(cloud_properties_with_location) }
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(cloud_properties_with_location['azure'], networks_spec)
          .and_return(network_configurator)
        allow(client2).to receive(:get_virtual_network_by_name)
          .with(default_resource_group_name, virtual_network_name)
          .and_return(vnet)
      end

      it 'should raise an error' do
        expect do
          cloud_with_location.create_vm(
            agent_id,
            stemcell_id,
            vm_properties,
            networks_spec,
            disk_locality,
            environment
          )
        end.to raise_error(/The location in the global configuration 'location-other-than-#{location}' is different from the location of the virtual network '#{location}'/)
      end
    end

    context 'when use_managed_disks is not set' do
      let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
      let(:instance_id_string) { 'fake-instance-id' }
      let(:vm_params) do
        {
          name: 'fake-vm-name'
        }
      end

      let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
      let(:storage_account) do
        {
          id: 'foo',
          name: storage_account_name,
          location: location,
          provisioning_state: 'bar',
          account_type: 'foo',
          storage_blob_host: 'fake-blob-endpoint',
          storage_table_host: 'fake-table-endpoint'
        }
      end

      before do
        allow(storage_account_manager).to receive(:get_storage_account_from_vm_properties)
          .with(vm_properties, location)
          .and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?)
          .with(storage_account_name, stemcell_id)
          .and_return(true)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config, networks_spec)
          .and_return(network_configurator)

        allow(Bosh::AzureCloud::InstanceId).to receive(:create)
          .with(default_resource_group_name, agent_id, storage_account_name)
          .and_return(instance_id)
        allow(instance_id).to receive(:to_s)
          .and_return(instance_id_string)
      end

      context 'when everything is OK' do
        context 'when resource group is specified' do
          let(:resource_group_name) { 'fake-resource-group-name' }
          let(:vm_properties) do
            {
              'instance_type' => 'fake-vm-size',
              'resource_group_name' => resource_group_name
            }
          end

          it 'should create the VM in the specified resource group' do
            expect(Bosh::AzureCloud::InstanceId).to receive(:create)
              .with(resource_group_name, agent_id, storage_account_name)
              .and_return(instance_id)
            expect(vm_manager).to receive(:create)
              .with(instance_id, location, stemcell_id, vm_properties, network_configurator, environment)
              .and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(
              cloud.create_vm(
                agent_id,
                stemcell_id,
                vm_properties,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id_string)
          end
        end
      end

      context 'when availability_zone is specified' do
        let(:vm_properties) do
          { 'availability_zone' => 'fake-az',
            'instance_type' => 'fake-vm-size' }
        end

        it 'should raise an error' do
          expect do
            cloud.create_vm(
              agent_id,
              stemcell_id,
              vm_properties,
              networks_spec,
              disk_locality,
              environment
            )
          end.to raise_error('Virtual Machines deployed to an Availability Zone must use managed disks')
        end
      end

      context 'when network configurator fails' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
            .and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect do
            cloud.create_vm(
              agent_id,
              stemcell_id,
              vm_properties,
              networks_spec,
              disk_locality,
              environment
            )
          end.to raise_error StandardError
        end
      end

      context 'when new vm is not created' do
        before do
          allow(vm_manager).to receive(:create).and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect do
            cloud.create_vm(
              agent_id,
              stemcell_id,
              vm_properties,
              networks_spec,
              disk_locality,
              environment
            )
          end.to raise_error StandardError
        end
      end

      context 'when registry fails to update' do
        before do
          allow(vm_manager).to receive(:create)
          allow(registry).to receive(:update_settings).and_raise(StandardError)
        end

        it 'deletes the vm' do
          expect(vm_manager).to receive(:delete).with(instance_id)

          expect do
            cloud.create_vm(
              agent_id,
              stemcell_id,
              vm_properties,
              networks_spec,
              disk_locality,
              environment
            )
          end.to raise_error(StandardError)
        end
      end
    end

    context 'when use_managed_disks is set' do
      let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
      let(:instance_id_string) { 'fake-instance-id' }
      let(:vm_params) do
        {
          name: 'fake-vm-name'
        }
      end

      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config_managed, networks_spec)
          .and_return(network_configurator)

        allow(Bosh::AzureCloud::InstanceId).to receive(:create)
          .with(default_resource_group_name, agent_id)
          .and_return(instance_id)
        allow(instance_id).to receive(:to_s)
          .and_return(instance_id_string)
      end

      context 'when resource group is specified' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:vm_properties) do
          {
            'instance_type' => 'fake-vm-size',
            'resource_group_name' => resource_group_name
          }
        end

        it 'should create the VM in the specified resource group' do
          expect(Bosh::AzureCloud::InstanceId).to receive(:create)
            .with(resource_group_name, agent_id)
            .and_return(instance_id)
          expect(vm_manager).to receive(:create)
            .with(instance_id, location, stemcell_id, vm_properties, network_configurator, environment)
            .and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              vm_properties,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id_string)
        end
      end
    end
  end
end
