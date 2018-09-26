# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#create_vm' do
    # Parameters
    let(:agent_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
    let(:stemcell_cid) { 'bosh-stemcell-e8ad4cab-befe-4e91-a139-f925830ffcbe' }
    let(:cloud_properties) { { 'instance_type' => 'fake-vm-size' } }
    let(:networks) { {} }
    let(:disk_cids) { double('disk_cids') }
    let(:environment) { double('environment') }

    let(:bosh_vm_meta) { Bosh::AzureCloud::BoshVMMeta.new(agent_id, stemcell_cid) }
    let(:vm_props) { cloud.props_factory.parse_vm_props(cloud_properties) }
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
      allow(azure_client).to receive(:get_virtual_network_by_name)
        .with(default_resource_group_name, virtual_network_name)
        .and_return(vnet)
      allow(telemetry_manager).to receive(:monitor)
        .with('create_vm', id: agent_id, extras: { 'instance_type' => 'fake-vm-size' })
        .and_call_original
      allow(cloud.props_factory).to receive(:parse_vm_props)
        .and_return(vm_props)
      allow(managed_cloud.props_factory).to receive(:parse_vm_props)
        .and_return(vm_props)
    end

    context 'when vnet is not found' do
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config, networks)
          .and_return(network_configurator)
        allow(azure_client).to receive(:get_virtual_network_by_name)
          .with(default_resource_group_name, virtual_network_name)
          .and_return(nil)
      end

      it 'should raise an error' do
        expect do
          cloud.create_vm(
            agent_id,
            stemcell_cid,
            cloud_properties,
            networks,
            disk_cids,
            environment
          )
        end.to raise_error(/Cannot find the virtual network '#{virtual_network_name}' under resource group '#{default_resource_group_name}'/)
      end
    end

    context 'when network/ephemeral_disk specified' do
      let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
      let(:instance_id_string) { 'fake-instance-id' }
      let(:vm_params) do
        {
          name: 'fake-vm-name',
          ephemeral_disk: {}
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
      let(:resource_group_name) { 'fake-resource-group-name' }
      let(:cloud_properties) do
        {
          'instance_type' => 'fake-vm-size',
          'resource_group_name' => resource_group_name
        }
      end

      let(:vm_props) do
        cloud.props_factory.parse_vm_props(
          cloud_properties
        )
      end
      let(:networks) do
        {
          'network_a' => {
            'dns' => ['172.30.22.153', '172.30.22.154']
          }
        }
      end
      before do
        allow(vm_manager).to receive(:get_storage_account_from_vm_properties)
          .with(vm_props, location)
          .and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?)
          .with(storage_account_name, stemcell_cid)
          .and_return(true)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config, networks)
          .and_return(network_configurator)
        allow(instance_id).to receive(:to_s)
          .and_return(instance_id_string)
        allow(Bosh::AzureCloud::BoshVMMeta).to receive(:new)
          .with(agent_id, stemcell_cid)
          .and_return(bosh_vm_meta)
        allow(cloud.props_factory).to receive(:parse_vm_props)
          .and_return(vm_props)
      end

      it 'should create the VM in the specified resource group' do
        expect(vm_manager).to receive(:create)
          .with(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, environment)
          .and_return([instance_id, vm_params])
        expect(registry_client).to receive(:update_settings)

        expect(
          cloud.create_vm(
            agent_id,
            stemcell_cid,
            cloud_properties,
            networks,
            disk_cids,
            environment
          )
        ).to eq(instance_id_string)
      end
    end

    context 'when the location in the global configuration is different from the vnet location' do
      let(:cloud_properties_with_location) { mock_cloud_properties_merge('azure' => { 'location' => "location-other-than-#{location}" }) }
      let(:cloud_with_location) { mock_cloud(cloud_properties_with_location) }
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(cloud_with_location.config.azure, networks)
          .and_return(network_configurator)
        allow(azure_client).to receive(:get_virtual_network_by_name)
          .with(default_resource_group_name, virtual_network_name)
          .and_return(vnet)
      end

      it 'should raise an error' do
        expect do
          cloud_with_location.create_vm(
            agent_id,
            stemcell_cid,
            cloud_properties,
            networks,
            disk_cids,
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
          instance_id: instance_id,
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
        allow(vm_manager).to receive(:get_storage_account_from_vm_properties)
          .with(vm_props, location)
          .and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?)
          .with(storage_account_name, stemcell_cid)
          .and_return(true)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config, networks)
          .and_return(network_configurator)
        allow(instance_id).to receive(:to_s)
          .and_return(instance_id_string)
        allow(Bosh::AzureCloud::BoshVMMeta).to receive(:new)
          .with(agent_id, stemcell_cid)
          .and_return(bosh_vm_meta)
      end

      context 'when everything is OK' do
        context 'when resource group is specified' do
          let(:resource_group_name) { 'fake-resource-group-name' }
          let(:cloud_properties) do
            {
              'instance_type' => 'fake-vm-size',
              'resource_group_name' => resource_group_name
            }
          end

          let(:vm_props) do
            cloud.props_factory.parse_vm_props(
              cloud_properties
            )
          end

          before do
            allow(cloud.props_factory).to receive(:parse_vm_props)
              .and_return(vm_props)
          end

          it 'should create the VM in the specified resource group' do
            expect(vm_manager).to receive(:create)
              .with(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, environment)
              .and_return([instance_id, vm_params])
            expect(registry_client).to receive(:update_settings)

            expect(
              cloud.create_vm(
                agent_id,
                stemcell_cid,
                cloud_properties,
                networks,
                disk_cids,
                environment
              )
            ).to eq(instance_id_string)
          end
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
              stemcell_cid,
              cloud_properties,
              networks,
              disk_cids,
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
              stemcell_cid,
              cloud_properties,
              networks,
              disk_cids,
              environment
            )
          end.to raise_error StandardError
        end
      end

      context 'when registry fails to update' do
        before do
          allow(vm_manager).to receive(:create)
            .and_return([instance_id, vm_params])
          allow(registry_client).to receive(:update_settings).and_raise(StandardError)
        end

        it 'deletes the vm' do
          expect(vm_manager).to receive(:delete).with(instance_id)

          expect do
            cloud.create_vm(
              agent_id,
              stemcell_cid,
              cloud_properties,
              networks,
              disk_cids,
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
          instance_id: instance_id,
          name: 'fake-vm-name'
        }
      end

      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new)
          .with(azure_config_managed, networks)
          .and_return(network_configurator)

        allow(instance_id).to receive(:to_s)
          .and_return(instance_id_string)
        allow(Bosh::AzureCloud::BoshVMMeta).to receive(:new)
          .with(agent_id, stemcell_cid)
          .and_return(bosh_vm_meta)
      end

      context 'when cloud_properties do not have instance_type, but have instance_types' do
        let(:instance_types) { ['fake-vm-size-1', 'fake-vm-size-2'] }
        let(:cloud_properties) { { 'instance_types' => instance_types } }
        let(:vm_props) { managed_cloud.props_factory.parse_vm_props(cloud_properties) }

        it 'should send instance_types as the telemetry data' do
          expect(telemetry_manager).to receive(:monitor)
            .with('create_vm', id: agent_id, extras: { 'instance_types' => instance_types })
            .and_call_original
          expect(vm_manager).to receive(:create)
            .with(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, environment)
            .and_return([instance_id, vm_params])
          expect(registry_client).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_cid,
              cloud_properties,
              networks,
              disk_cids,
              environment
            )
          ).to eq(instance_id_string)
        end
      end

      context 'when resource group is specified' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:cloud_properties) do
          {
            'instance_type' => 'fake-vm-size',
            'resource_group_name' => resource_group_name
          }
        end
        let(:vm_props) { managed_cloud.props_factory.parse_vm_props(cloud_properties) }

        it 'should create the VM in the specified resource group' do
          expect(vm_manager).to receive(:create)
            .with(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, environment)
            .and_return([instance_id, vm_params])
          expect(registry_client).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_cid,
              cloud_properties,
              networks,
              disk_cids,
              environment
            )
          ).to eq(instance_id_string)
        end
      end
    end
  end
end
