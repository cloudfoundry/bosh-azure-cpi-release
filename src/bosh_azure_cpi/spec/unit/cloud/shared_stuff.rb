# frozen_string_literal: true

shared_context 'shared stuff' do
  let(:cloud) { mock_cloud }
  let(:registry_client) { mock_registry }
  let(:azure_config) { cloud.config.azure }
  let(:managed_cloud) { mock_cloud(mock_cloud_properties_merge('azure' => { 'use_managed_disks' => true })) }
  let(:use_vmss_cloud) do
    mock_cloud(
      mock_cloud_properties_merge(
        'azure' => {
          'use_managed_disks' => true,
          'config_disk' => {
            'enabled' => true
          },
          'vmss' => {
            'enabled' => true
          }
        }
      )
    )
  end
  let(:azure_config_managed) { managed_cloud.config.azure }
  let(:azure_client) { instance_double('Bosh::AzureCloud::AzureClient') }
  let(:blob_manager) { instance_double('Bosh::AzureCloud::BlobManager') }
  let(:disk_manager) { instance_double('Bosh::AzureCloud::DiskManager') }
  let(:storage_account_manager) { instance_double('Bosh::AzureCloud::StorageAccountManager') }
  let(:table_manager) { instance_double('Bosh::AzureCloud::TableManager') }
  let(:stemcell_manager) { instance_double('Bosh::AzureCloud::StemcellManager') }
  let(:disk_manager2) { instance_double('Bosh::AzureCloud::DiskManager2') }
  let(:stemcell_manager2) { instance_double('Bosh::AzureCloud::StemcellManager2') }
  let(:light_stemcell_manager) { instance_double('Bosh::AzureCloud::LightStemcellManager') }
  let(:vm_manager) { instance_double('Bosh::AzureCloud::VMManager') }
  let(:instance_type_mapper) { instance_double('Bosh::AzureCloud::InstanceTypeMapper') }
  let(:telemetry_manager) { MockTelemetryManager.new }

  # models
  let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
  let(:agent_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
  let(:stemcell_id) { 'bosh-stemcell-xxx' }
  let(:instance_id) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
  let(:vm_name) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
  let(:instance_id_object) { Bosh::AzureCloud::VMInstanceId.create_from_hash({}, instance_id) }

  let(:vmss_name) { 'fake-vmss-name' }
  let(:vmss_instance_id) { '0' }
  let(:instance_id_vmss) { "resource_group_name:#{default_resource_group_name};agent_id:a;vmss_name:v;vmss_instance_id:0" }

  let(:disk_id) { 'bosh-disk-data-0a1171c3-d9a6-4a04-96cb-e422c1f49a7b' }
  let(:disk_id_object) { Bosh::AzureCloud::DiskId.create_from_hash({}, disk_id) }
  let(:disk_name) { 'bosh-disk-data-0a1171c3-d9a6-4a04-96cb-e422c1f49a7b' }
  let(:bosh_vm_meta) { Bosh::AzureCloud::BoshVMMeta.new(agent_id, stemcell_id) }

  before do
    allow(Bosh::Cpi::RegistryClient).to receive(:new)
      .and_return(registry_client)
    allow(Bosh::AzureCloud::AzureClient).to receive(:new)
      .and_return(azure_client)
    allow(Bosh::AzureCloud::BlobManager).to receive(:new)
      .and_return(blob_manager)
    allow(Bosh::AzureCloud::DiskManager).to receive(:new)
      .and_return(disk_manager)
    allow(Bosh::AzureCloud::StorageAccountManager).to receive(:new)
      .and_return(storage_account_manager)
    allow(Bosh::AzureCloud::TableManager).to receive(:new)
      .and_return(table_manager)
    allow(Bosh::AzureCloud::StemcellManager).to receive(:new)
      .and_return(stemcell_manager)
    allow(Bosh::AzureCloud::DiskManager2).to receive(:new)
      .and_return(disk_manager2)
    allow(Bosh::AzureCloud::StemcellManager2).to receive(:new)
      .and_return(stemcell_manager2)
    allow(Bosh::AzureCloud::LightStemcellManager).to receive(:new)
      .and_return(light_stemcell_manager)
    allow(Bosh::AzureCloud::VMManager).to receive(:new)
      .and_return(vm_manager)
    allow(Bosh::AzureCloud::InstanceTypeMapper).to receive(:new)
      .and_return(instance_type_mapper)
    allow(Bosh::AzureCloud::TelemetryManager).to receive(:new)
      .and_return(telemetry_manager)
    allow(telemetry_manager).to receive(:monitor)
      .with('initialize').and_call_original
  end
end
