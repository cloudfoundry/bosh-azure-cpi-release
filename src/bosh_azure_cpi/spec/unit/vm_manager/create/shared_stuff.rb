# The following default configurations are shared. If one case needs a specific configuration, it should overwrite it.
shared_context "shared stuff for vm manager" do
  # Parameters of VMManager.initialize
  let(:azure_properties) { mock_azure_properties }
  let(:azure_properties_managed) {
    mock_azure_properties_merge({
      'use_managed_disks' => true
    })
  }
  let(:registry_endpoint) { mock_registry.endpoint }
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
  let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }

  # VM manager for unmanaged disks
  let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_properties, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager) }
  # VM manager for managed disks
  let(:vm_manager2) { Bosh::AzureCloud::VMManager.new(azure_properties_managed, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager) }

  # Parameters of create
  let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
  let(:location) { "fake-location" }
  let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }
  let(:resource_pool) {
    {
      'instance_type'         => 'Standard_D1',
      'storage_account_name'  => 'dfe03ad623f34d42999e93ca',
      'caching'               => 'ReadWrite',
      'load_balancer'         => 'fake-lb-name'
    }
  }
  let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }
  let(:env) { {} }

  # Instance ID
  let(:resource_group_name) { "fake-resource-group-name" }
  let(:vm_name) { "fake-vm-name" }
  let(:storage_account_name) { "fake-storage-acount-name" }
  let(:instance_id_string) { "fake-instance-id" }
  before do
    allow(instance_id).to receive(:resource_group_name).
      and_return(resource_group_name)
    allow(instance_id).to receive(:vm_name).
      and_return(vm_name)
    allow(instance_id).to receive(:storage_account_name).
      and_return(storage_account_name)
    allow(instance_id).to receive(:to_s).
      and_return(instance_id_string)
  end

  # Stemcell
  let(:stemcell_uri) { "fake-uri" }
  let(:os_type) { "fake-os-type" }
  before do
    allow(stemcell_info).to receive(:uri).
      and_return(stemcell_uri)
    allow(stemcell_info).to receive(:os_type).
      and_return(os_type)
    allow(stemcell_info).to receive(:is_windows?).
      and_return(false)
    allow(stemcell_info).to receive(:image_size).
      and_return(nil)
    allow(stemcell_info).to receive(:is_light_stemcell?).
      and_return(false)
  end

  # AzureClient2
  let(:subnet) { double("subnet") }
  let(:security_group) {
    {
      :name => MOCK_DEFAULT_SECURITY_GROUP,
      :id   => "fake-nsg-id"
    }
  }
  let(:load_balancer) {
    {
      :name => "fake-lb-name"
    }
  }
  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(client2)
    allow(client2).to receive(:get_network_subnet_by_name).
      with(MOCK_RESOURCE_GROUP_NAME, "fake-virtual-network-name", "fake-subnet-name").
      and_return(subnet)
    allow(client2).to receive(:get_network_security_group_by_name).
      with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
      and_return(security_group)
    allow(client2).to receive(:get_load_balancer_by_name).
      with(resource_pool['load_balancer']).
      and_return(load_balancer)
    allow(client2).to receive(:get_public_ip_by_name).
      with(resource_group_name, vm_name).
      and_return(nil)
    allow(client2).to receive(:get_resource_group).
      and_return({})
  end

  # Network
  let(:vip_network) { instance_double(Bosh::AzureCloud::VipNetwork) }
  let(:manual_network) { instance_double(Bosh::AzureCloud::ManualNetwork) }
  let(:dynamic_network) { instance_double(Bosh::AzureCloud::DynamicNetwork) }
  before do
    allow(network_configurator).to receive(:vip_network).
      and_return(vip_network)
    allow(network_configurator).to receive(:networks).
      and_return([manual_network, dynamic_network])
    allow(network_configurator).to receive(:default_dns).
      and_return("fake-dns")

    allow(vip_network).to receive(:resource_group_name).
      and_return('fake-resource-group')
    allow(client2).to receive(:list_public_ips).
      and_return([{
        :ip_address => "public-ip"
      }])
    allow(vip_network).to receive(:public_ip).
      and_return('public-ip')

    allow(manual_network).to receive(:resource_group_name).
      and_return(MOCK_RESOURCE_GROUP_NAME)
    allow(manual_network).to receive(:security_group).
      and_return(nil)
    allow(manual_network).to receive(:virtual_network_name).
      and_return("fake-virtual-network-name")
    allow(manual_network).to receive(:subnet_name).
      and_return("fake-subnet-name")
    allow(manual_network).to receive(:private_ip).
      and_return('private-ip')

    allow(dynamic_network).to receive(:resource_group_name).
      and_return(MOCK_RESOURCE_GROUP_NAME)
    allow(dynamic_network).to receive(:security_group).
      and_return(nil)
    allow(dynamic_network).to receive(:virtual_network_name).
      and_return("fake-virtual-network-name")
    allow(dynamic_network).to receive(:subnet_name).
      and_return("fake-subnet-name")
  end

  # Disk
  let(:os_disk_name) { "fake-os-disk-name" }
  let(:ephemeral_disk_name) { "fake-ephemeral-disk-name" }
  let(:os_disk) {
    {
      :disk_name    => "fake-disk-name",
      :disk_uri     => "fake-disk-uri",
      :disk_size    => "fake-disk-size",
      :disk_caching => "fake-disk-caching"
    }
  }
  let(:ephemeral_disk) {
    {
      :disk_name    => 'fake-disk-name',
      :disk_uri     => 'fake-disk-uri',
      :disk_size    => 'fake-disk-size',
      :disk_caching => 'fake-disk-caching'
    }
  }
  let(:os_disk_managed) {
    {
      :disk_name    => 'fake-disk-name',
      :disk_size    => 'fake-disk-size',
      :disk_caching => 'fake-disk-caching'
    }
  }
  let(:ephemeral_disk_managed) {
    {
      :disk_name    => 'fake-disk-name',
      :disk_size    => 'fake-disk-size',
      :disk_caching => 'fake-disk-caching'
    }
  }
  before do
    allow(disk_manager).to receive(:delete_disk).
      and_return(nil)
    allow(disk_manager).to receive(:generate_os_disk_name).
      and_return(os_disk_name)
    allow(disk_manager).to receive(:generate_ephemeral_disk_name).
      and_return(ephemeral_disk_name)
    allow(disk_manager).to receive(:resource_pool=)
    allow(disk_manager).to receive(:os_disk).
      and_return(os_disk)
    allow(disk_manager).to receive(:ephemeral_disk).
      and_return(ephemeral_disk)
    allow(disk_manager).to receive(:delete_vm_status_files).
      and_return(nil)

    allow(disk_manager2).to receive(:generate_os_disk_name).
      and_return(os_disk_name)
    allow(disk_manager2).to receive(:generate_ephemeral_disk_name).
      and_return(ephemeral_disk_name)
    allow(disk_manager2).to receive(:resource_pool=)
    allow(disk_manager2).to receive(:os_disk).
      and_return(os_disk_managed)
    allow(disk_manager2).to receive(:ephemeral_disk).
      and_return(ephemeral_disk_managed)
  end

  # Network Interface
  let(:network_interface) {
    {
      :name => "foo"
    }
  }
  before do
    allow(client2).to receive(:create_network_interface)
    allow(client2).to receive(:get_network_interface_by_name).
      and_return(network_interface)
  end
end
