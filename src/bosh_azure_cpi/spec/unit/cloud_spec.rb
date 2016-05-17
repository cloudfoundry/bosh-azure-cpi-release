require 'spec_helper'

describe Bosh::AzureCloud::Cloud do
  let(:cloud) { mock_cloud }
  let(:registry) { mock_registry }
  let(:azure_properties) { mock_azure_properties }

  let(:client2) { instance_double('Bosh::AzureCloud::AzureClient2') }
  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(client2)
  end

  let(:blob_manager) { instance_double('Bosh::AzureCloud::BlobManager') }
  let(:table_manager) { instance_double('Bosh::AzureCloud::TableManager') }
  let(:stemcell_manager) { instance_double('Bosh::AzureCloud::StemcellManager') }
  let(:disk_manager) { instance_double('Bosh::AzureCloud::DiskManager') }
  let(:vm_manager) { instance_double('Bosh::AzureCloud::VMManager') }
  before do
    allow(Bosh::AzureCloud::BlobManager).to receive(:new).
      and_return(blob_manager)
    allow(Bosh::AzureCloud::TableManager).to receive(:new).
      and_return(table_manager)
    allow(Bosh::AzureCloud::StemcellManager).to receive(:new).
      and_return(stemcell_manager)
    allow(Bosh::AzureCloud::DiskManager).to receive(:new).
      and_return(disk_manager)
    allow(Bosh::AzureCloud::VMManager).to receive(:new).
      and_return(vm_manager)
  end

  let(:uuid) { 'e55144a3-0c06-4240-8f15-9a7bc7b35d1f' }
  let(:instance_id) { "#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}-#{uuid}" }
  let(:disk_id) { "fake-disk-id" }
  let(:stemcell_id) { "fake-stemcell-id" }
  let(:agent_id) { "fake-agent-id" }
  let(:snapshot_id) { 'fake-snapshot-id' }

  describe '#initialize' do
    context 'when all the required configurations are present' do
      it 'should not raise an error ' do
        expect { cloud }.not_to raise_error
      end
    end

    context 'when options are invalid' do
      let(:options) do
        {
          'azure' => {
            'environment' => 'AzureCloud',
            'api_version' => '2015-05-01-preview',
            'subscription_id' => "foo",
            'storage_account_name' => 'mock_storage_name',
            'storage_access_key' => "foo",
            'resource_group_name' => 'mock_resource_group',
            'ssh_public_key' => "foo",
          }
        }
      end

      let(:cloud) { mock_cloud(options) }

      it 'should raise an error' do
        expect { cloud }.to raise_error(
          ArgumentError,
          'missing configuration parameters > azure:ssh_user, azure:tenant_id, azure:client_id, azure:client_secret, azure:default_security_group, registry:endpoint, registry:user, registry:password'
        )
      end
    end

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
    it 'should delete a stemcell' do
      expect(stemcell_manager).to receive(:delete_stemcell).with(stemcell_id)

      cloud.delete_stemcell(stemcell_id)
    end
  end

  describe '#create_vm' do
    let(:storage_account_name) { azure_properties['storage_account_name'] }
    let(:stemcell_uri) {
      "https://#{storage_account_name}.blob.core.windows.net/fakecontainer/#{stemcell_id}.vhd"
    }
    let(:resource_pool) { {'instance_type' => 'fake-vm-size'} }
    let(:networks_spec) { {} }
    let(:disk_locality) { double("disk locality") }
    let(:environment) { double("environment") }
    let(:network_configurator) { double("network configurator") }
    let(:storage_account) {
      {
        :id => "foo",
        :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
        :location => "bar",
        :provisioning_state => "bar",
        :account_type => "foo",
        :storage_blob_host => "fake-blob-endpoint",
        :storage_table_host => "fake-table-endpoint"
      }
    }

    before do
      allow(stemcell_manager).to receive(:has_stemcell?).
        with(storage_account_name, stemcell_id).
        and_return(true)
      allow(stemcell_manager).to receive(:get_stemcell_uri).
        with(storage_account_name, stemcell_id).
        and_return(stemcell_uri)
      allow(vm_manager).to receive(:create).and_return(instance_id)
      allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(networks_spec).
          and_return(network_configurator)
      allow(registry).to receive(:update_settings)
      allow(client2).to receive(:get_storage_account_by_name).
        and_return(storage_account)
    end

    context 'when everything is fine' do
      context "when using the default storage account" do
          it 'should not raise any error' do
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

      context "when do not use the default storage account" do
        let(:storage_account_name) { 'fake-storage-account-name' }
        let(:resource_pool) {
          {
            'instance_type' => 'fake-vm-size',
            'storage_account_name'=>'fake-storage-account-name'
          }
        }

        before do
          allow(stemcell_manager).to receive(:has_stemcell?).
            with(storage_account_name, stemcell_id).
            and_return(true)
          allow(stemcell_manager).to receive(:get_stemcell_uri).
            with(storage_account_name, stemcell_id).
            and_return(stemcell_uri)
        end

        context "when the storage account does not exist" do
          before do
            allow(client2).to receive(:get_storage_account_by_name).and_return(nil)
            allow(cloud).to receive(:create_storage_account).and_return(true)
          end

          it 'should not raise any error' do
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

        context "when the storage account exists" do
          let(:storage_account) { 'fake-storage-account' }

          before do
            allow(client2).to receive(:get_storage_account_by_name).and_return(storage_account)
          end

          it 'should not raise any error' do
            expect(cloud).not_to receive(:create_storage_account)
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
    end

    context 'when instance_type is not provided' do
      it 'should raise an error' do
        expect {
          cloud.create_vm(
            agent_id,
            stemcell_id,
            {},
            networks_spec,
            disk_locality,
            environment
          )
        }.to raise_error("missing required cloud property `instance_type'.")
      end
    end

    context "when the storage account name is invalid" do
      let(:resource_pool) {
        {
          'instance_type' => 'fake-vm-size',
          'storage_account_name'=>'fake-storage-account-name'
        }
      }

      before do
        allow(client2).to receive(:get_storage_account_by_name).and_return(nil)
        allow(cloud).to receive(:create_storage_account).and_raise("The storage account name is invalid")
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
        }.to raise_error(/The storage account name is invalid/)
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
        }.to raise_error("Given stemcell '#{stemcell_id}' does not exist")
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

  describe "#delete_vm" do
    it 'should delete an instance' do
      expect(vm_manager).to receive(:delete).with(instance_id)

      cloud.delete_vm(instance_id)
    end
  end

  describe '#has_vm?' do
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
    it 'reboot an instance' do
      expect(vm_manager).to receive(:reboot).with(instance_id)

      cloud.reboot_vm(instance_id)
    end
  end

  describe '#set_vm_metadata' do
    let(:metadata) { {"user-agent"=>"bosh"} }

    it 'should set the vm metadata' do
      expect(vm_manager).to receive(:set_metadata).with(instance_id, metadata)

      cloud.set_vm_metadata(instance_id, metadata)
    end
  end

  describe '#configure_networks' do
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
    let(:cloud_properties) { {} }

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

    context 'when disk size is larger than 1 TiB' do
      let(:disk_size) { 2000000 }

      it 'should raise an error' do
        expect {
          cloud.create_disk(disk_size, cloud_properties, instance_id)
        }.to raise_error /Azure CPI maximum disk size is 1 TiB/
      end
    end
  end

  describe "#delete_disk" do
    it 'should delete the disk' do
      expect(disk_manager).to receive(:delete_disk).with(disk_id)

      cloud.delete_disk(disk_id)
    end
  end

  describe "#attach_disk" do
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

    it 'should take a snapshot of a disk' do
      expect(disk_manager).to receive(:snapshot_disk).
        with(disk_id, metadata).
        and_return(snapshot_id)

      expect(cloud.snapshot_disk(disk_id, metadata)).to eq(snapshot_id)
    end
  end

  describe "#delete_snapshot" do
    it 'should delete the snapshot' do
      expect(disk_manager).to receive(:delete_snapshot).with(snapshot_id)

      cloud.delete_snapshot(snapshot_id)
    end
  end

  describe "#detach_disk" do
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
