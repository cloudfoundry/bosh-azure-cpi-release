require 'spec_helper'

describe Bosh::AzureCloud::Cloud do
  let(:cloud) { mock_cloud }
  let(:registry) { mock_registry }
  let(:azure_properties) { mock_azure_properties }
  let(:azure_properties_managed) {
    mock_azure_properties_merge({
      'use_managed_disks' => true
    })
  }

  let(:client2) { instance_double('Bosh::AzureCloud::AzureClient2') }
  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(client2)
  end

  let(:storage_account_manager) { instance_double('Bosh::AzureCloud::StorageAccountManager') }
  let(:blob_manager) { instance_double('Bosh::AzureCloud::BlobManager') }
  let(:table_manager) { instance_double('Bosh::AzureCloud::TableManager') }
  let(:stemcell_manager) { instance_double('Bosh::AzureCloud::StemcellManager') }
  let(:stemcell_manager2) { instance_double('Bosh::AzureCloud::StemcellManager2') }
  let(:disk_manager) { instance_double('Bosh::AzureCloud::DiskManager') }
  let(:disk_manager2) { instance_double('Bosh::AzureCloud::DiskManager2') }
  let(:vm_manager) { instance_double('Bosh::AzureCloud::VMManager') }

  before do
    allow(Bosh::AzureCloud::BlobManager).to receive(:new).
      and_return(blob_manager)
    allow(Bosh::AzureCloud::StorageAccountManager).to receive(:new).
      and_return(storage_account_manager)
    allow(Bosh::AzureCloud::TableManager).to receive(:new).
      and_return(table_manager)
    allow(Bosh::AzureCloud::StemcellManager).to receive(:new).
      and_return(stemcell_manager)
    allow(Bosh::AzureCloud::DiskManager).to receive(:new).
      and_return(disk_manager)
    allow(Bosh::AzureCloud::StemcellManager2).to receive(:new).
      and_return(stemcell_manager2)
    allow(Bosh::AzureCloud::DiskManager2).to receive(:new).
      and_return(disk_manager2)
    allow(Bosh::AzureCloud::VMManager).to receive(:new).
      and_return(vm_manager)
  end

  describe '#initialize' do
    context 'when there is no proper network access to Azure' do
      let(:storage_account) {
        {
          :id => "foo",
          :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
          :location => "bar",
          :provisioning_state => "bar",
          :account_type => "foo",
          :primary_endpoints => "bar"
        }
      }
      before do
        allow(client2).to receive(:get_storage_account_by_name).and_return(storage_account)
        allow(Bosh::AzureCloud::TableManager).to receive(:new).and_raise(Net::OpenTimeout, 'execution expired')
      end

      it 'raises an exception with a user friendly message' do
        expect { cloud }.to raise_error(Bosh::Clouds::CloudError, 'Please make sure the CPI has proper network access to Azure. #<Net::OpenTimeout: execution expired>')
      end
    end
  end

  describe '#create_stemcell' do
    # Parameters
    let(:stemcell_id) { "fake-stemcell-id" }

    let(:cloud_properties) { {} }
    let(:image_path) { "fake-image-path" }

    it 'should create a stemcell' do
      expect(stemcell_manager).to receive(:create_stemcell).
        with(image_path, cloud_properties).and_return(stemcell_id)

      expect(
        cloud.create_stemcell(image_path, cloud_properties)
      ).to eq(stemcell_id)
    end
  end

  describe '#delete_stemcell' do
    # Parameters
    let(:stemcell_id) { "fake-stemcell-id" }

    it 'should delete a stemcell' do
      expect(stemcell_manager).to receive(:delete_stemcell).with(stemcell_id)

      cloud.delete_stemcell(stemcell_id)
    end
  end

  describe '#create_vm' do
    # Parameters
    let(:agent_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:stemcell_id) { "fake-stemcell-id" }
    let(:resource_pool) { {'instance_type' => 'fake-vm-size'} }
    let(:networks_spec) { {} }
    let(:disk_locality) { double("disk locality") }
    let(:environment) { double("environment") }

    let(:network_configurator) { double("network configurator") }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }

    context 'when use_managed_disks is not set' do
      # The return value of create_vm
      let(:instance_id) { "#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}-#{agent_id}" }
      let(:vm_params) {
        {
          :name => instance_id
        }
      }

      let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
      let(:location) { "fake-location" }
      let(:storage_account) {
        {
          :id => "foo",
          :name => storage_account_name,
          :location => location,
          :provisioning_state => "bar",
          :account_type => "foo",
          :storage_blob_host => "fake-blob-endpoint",
          :storage_table_host => "fake-table-endpoint"
        }
      }

      before do
        allow(storage_account_manager).to receive(:get_storage_account_from_resource_pool).
          with(resource_pool).
          and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?).
          with(storage_account_name, stemcell_id).
          and_return(true)
        allow(stemcell_manager).to receive(:get_stemcell_info).
          with(storage_account_name, stemcell_id).
          and_return(stemcell_info)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties, networks_spec).
          and_return(network_configurator)
      end

      context 'when everything is OK' do
        it 'should create the VM' do
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id)
        end
      end

      context 'when stemcell_id is invalid' do
        before do
          allow(stemcell_manager).to receive(:has_stemcell?).
            with(storage_account_name, stemcell_id).
            and_return(false)
        end

        it 'should raise an error' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error("Given stemcell `#{stemcell_id}' does not exist")
        end
      end

      context 'when network configurator fails' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
            and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error
        end
      end

      context 'when new vm is not created' do
        before do
          allow(vm_manager).to receive(:create).and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error
        end
      end

      context 'when registry fails to update' do
        before do
          allow(vm_manager).to receive(:create)
          allow(registry).to receive(:update_settings).and_raise(StandardError)
        end

        it 'deletes the vm' do
          expect(vm_manager).to receive(:delete).with(instance_id)

          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error(StandardError)
        end
      end
    end

    context 'when use_managed_disks is set' do
      # The return value of create_vm
      let(:instance_id) { agent_id }
      let(:vm_params) {
        {
          :name => instance_id
        }
      }

      let(:cloud) { mock_cloud(mock_cloud_properties_merge({'azure' => {'use_managed_disks' => true}})) }

      let(:location) { "fake-location" }
      let(:resource_group) {
        {
          :location => location
        }
      }

      before do
        allow(client2).to receive(:get_resource_group).
          and_return(resource_group)
        allow(stemcell_manager2).to receive(:get_user_image_info).
          and_return(stemcell_info)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties_managed, networks_spec).
          and_return(network_configurator)
      end

      it 'should create the VM' do
        expect(vm_manager).to receive(:create).
          with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
          and_return(vm_params)
        expect(registry).to receive(:update_settings)

        expect(
          cloud.create_vm(
            agent_id,
            stemcell_id,
            resource_pool,
            networks_spec,
            disk_locality,
            environment
          )
        ).to eq(instance_id)
      end
    end
  end

  describe "#delete_vm" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    it 'should delete an instance' do
      expect(vm_manager).to receive(:delete).with(instance_id)

      cloud.delete_vm(instance_id)
    end
  end

  describe '#has_vm?' do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    let(:instance) { double("instance") }

    context "when the instance exists" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id).
          and_return(instance)
        allow(instance).to receive(:[]).with(:provisioning_state).
          and_return('Running')
      end

      it "should return true" do
        expect(cloud.has_vm?(instance_id)).to be(true)
      end
    end

    context "when the instance doesn't exists" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id).and_return(nil)
      end

      it "returns false if the instance doesn't exists" do
        expect(cloud.has_vm?(instance_id)).to be(false)
      end
    end

    context "when the instance state is deleting" do
      before do
        allow(vm_manager).to receive(:find).with(instance_id).
          and_return(instance)
        allow(instance).to receive(:[]).with(:provisioning_state).
          and_return('Deleting')
      end

      it 'returns false if the instance state is deleting' do
        expect(cloud.has_vm?(instance_id)).to be(false)
      end
    end
  end

  describe "#has_disk?" do
    # Parameters
    let(:disk_id) { "fake-disk-id" }

    context 'when the disk exists' do
      it 'should return true' do
        expect(disk_manager).to receive(:has_disk?).with(disk_id).and_return(true)

        expect(cloud.has_disk?(disk_id)).to be(true)
      end
    end

    context 'when the disk does not exist' do
      it 'should return false' do
        expect(disk_manager).to receive(:has_disk?).with(disk_id).and_return(false)

        expect(cloud.has_disk?(disk_id)).to be(false)
      end
    end
  end

  describe "#reboot_vm" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    it 'reboot an instance' do
      expect(vm_manager).to receive(:reboot).with(instance_id)

      cloud.reboot_vm(instance_id)
    end
  end

  describe '#set_vm_metadata' do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:metadata) { {"user-agent"=>"bosh"} }

    it 'should set the vm metadata' do
      expect(vm_manager).to receive(:set_metadata).with(instance_id, metadata)

      cloud.set_vm_metadata(instance_id, metadata)
    end
  end

  describe '#configure_networks' do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:networks) { "networks" }

    it 'should raise a NotSupported error' do
      expect {
        cloud.configure_networks(instance_id, networks)
      }.to raise_error {
        Bosh::Clouds::NotSupported
      }
    end
  end

  describe '#create_disk' do
    # Parameters
    let(:cloud_properties) { {} }
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    context 'when disk size is not an integer' do
      let(:disk_size) { 1024.42 }

      it 'should raise an error' do
        expect {
          cloud.create_disk(disk_size, cloud_properties, instance_id)
        }.to raise_error(
          ArgumentError,
          'disk size needs to be an integer'
        )
      end
    end

    context 'when disk size is smaller than 1 GiB' do
      let(:disk_size) { 100 }

      it 'should raise an error' do
        expect {
          cloud.create_disk(disk_size, cloud_properties, instance_id)
        }.to raise_error /Azure CPI minimum disk size is 1 GiB/
      end
    end

    context 'when disk size is larger than 1023 GiB' do
      let(:disk_size) { 1024 * 1024 }

      it 'should raise an error' do
        expect {
          cloud.create_disk(disk_size, cloud_properties, instance_id)
        }.to raise_error /Azure CPI maximum disk size is 1023 GiB/
      end
    end

    context "when caching is invalid in cloud_properties" do
      let(:disk_size) { 100 * 1024 }
      let(:cloud_properties) {
        {
          "caching" => "Invalid"
        }
      }

      it "should raise an error" do
        expect {
          cloud.create_disk(disk_size, cloud_properties, instance_id)
        }.to raise_error /Unknown disk caching/
      end
    end

    # TODO
    #context "when caching is nil in cloud_properties" do
    #  let(:disk_size) { 100 * 1024 }

    #  it "should use the default caching None" do
    #    expect(cloud.create_disk(disk_size, cloud_properties, instance_id)).to include("None")
    #  end
    #end

    #context "when caching is specified in cloud_properties" do
    #  let(:disk_size) { 100 * 1024 }
    #  let(:cloud_properties) {
    #    {
    #      "caching" => "ReadOnly"
    #    }
    #  }

    #  it "should use the default caching None" do
    #    expect(cloud.create_disk(disk_size, cloud_properties, instance_id)).to include("ReadOnly")
    #  end
    #end
  end

  describe "#delete_disk" do
    # Parameters
    let(:disk_id) { "fake-disk-id" }

    it 'should delete the disk' do
      expect(disk_manager).to receive(:delete_disk).with(disk_id)

      cloud.delete_disk(disk_id)
    end
  end

  describe "#attach_disk" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:disk_id) { "fake-disk-id" }

    let(:volume_name) { '/dev/sdd' }
    let(:lun) { '1' }
    let(:host_device_id) { '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}' }

    before do
      allow(vm_manager).to receive(:attach_disk).with(instance_id, disk_id).
        and_return(lun)
    end

    it 'attaches the disk to the vm' do
      old_settings = { 'foo' => 'bar'}
      new_settings = {
        'foo' => 'bar',
        'disks' => {
          'persistent' => {
            disk_id => {
              'lun' => lun,
              'host_device_id' => host_device_id,
              'path' => volume_name
            }
          }
        }
      }

      expect(registry).to receive(:read_settings).with(instance_id).
        and_return(old_settings)
      expect(registry).to receive(:update_settings).
        with(instance_id, new_settings).and_return(true)

      cloud.attach_disk(instance_id, disk_id)
    end
  end

  describe "#snapshot_disk" do
    let(:metadata) { {} }
    let(:snapshot_id) { 'fake-snapshot-id' }

    context "when the disk is a managed disk" do
      context "when the disk starts with bosh-disk-data" do
        let(:disk_id) { "bosh-disk-data-fake-guid" }

        it 'should take a managed snapshot of the disk' do
          expect(disk_manager2).to receive(:snapshot_disk).
            with(disk_id, metadata).
            and_return(snapshot_id)

          expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
        end
      end

      context "when the disk starts with bosh-disk-data" do
        let(:disk_id) { "fakestorageaccountname-fake-guid" }

        before do
          expect(disk_manager2).to receive(:get_disk).
            with(disk_id).
            and_return({:name=>disk_id})
        end

        it 'should take a managed snapshot of the disk' do
          expect(disk_manager2).to receive(:snapshot_disk).
            with(disk_id, metadata).
            and_return(snapshot_id)

          expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
        end
      end
    end

    context "when the disk is an unmanaged disk" do
      let(:disk_id) { "fakestorageaccountname-fake-guid" }

      before do
        expect(disk_manager2).to receive(:get_disk).
          with(disk_id).
          and_return(nil)
      end

      it 'should take an unmanaged snapshot of the disk' do
        expect(disk_manager).to receive(:snapshot_disk).
          with(disk_id, metadata).
          and_return(snapshot_id)

        expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
      end
    end
  end

  describe "#delete_snapshot" do
    context "when the snapshot is a managed snapshot" do
      let(:snapshot_id) { 'bosh-disk-data-fake-guid' }

      it 'should delete the managed snapshot' do
        expect(disk_manager2).to receive(:delete_snapshot).with(snapshot_id)

        cloud.delete_snapshot(snapshot_id)
      end
    end

    context "when the snapshot is an unmanaged snapshot" do
      let(:snapshot_id) { 'fake-snapshot-id' }

      it 'should delete the unmanaged snapshot' do
        expect(disk_manager).to receive(:delete_snapshot).with(snapshot_id)

        cloud.delete_snapshot(snapshot_id)
      end
    end
  end

  describe "#detach_disk" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:disk_id) { "fake-disk-id" }

    let(:host_device_id) { 'fake-host-device-id' }
  
    it 'detaches the disk from the vm' do
      old_settings = {
        "foo" => "bar",
        "disks" => {
          "persistent" => {
            "fake-disk-id" =>  {
              'lun'      => '1',
              'host_device_id' => host_device_id,
              'path' => '/dev/sdd'
            },
            "v-deadbeef" =>  {
              'lun'      => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      new_settings = {
        "foo" => "bar",
        "disks" => {
          "persistent" => {
            "v-deadbeef" => {
              'lun' => '2',
              'host_device_id' => host_device_id,
              'path' => '/dev/sde'
            }
          }
        }
      }

      expect(registry).to receive(:read_settings).
        with(instance_id).
        and_return(old_settings)
      expect(registry).to receive(:update_settings).
        with(instance_id, new_settings)

      expect(vm_manager).to receive(:detach_disk).with(instance_id, disk_id)

      cloud.detach_disk(instance_id, disk_id)
    end
  end

  describe "#get_disks" do
    # Parameters
    let(:instance_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }

    let(:data_disks) {
      [
        {
          :name => "fake-data-disk-1",
        }, {
          :name => "fake-data-disk-2",
        }, {
          :name => "fake-data-disk-3",
        }
      ]
    }
    let(:instance) {
      {
        :data_disks    => data_disks,
      }
    }
    let(:instance_no_disks) {
      {
        :data_disks    => {},
      }
    }
  
    context 'when the instance has data disks' do
      it 'should get a list of disk id' do
        expect(vm_manager).to receive(:find).
          with(instance_id).
          and_return(instance)

        expect(cloud.get_disks(instance_id)).to eq(["fake-data-disk-1", "fake-data-disk-2", "fake-data-disk-3"])
      end
    end

    context 'when the instance has no data disk' do
      it 'should get a empty list' do
        expect(vm_manager).to receive(:find).
          with(instance_id).
          and_return(instance_no_disks)

        expect(cloud.get_disks(instance_id)).to eq([])
      end
    end
  end

end
