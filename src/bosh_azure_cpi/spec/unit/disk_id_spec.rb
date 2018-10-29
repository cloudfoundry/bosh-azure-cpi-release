# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::DiskId do
  describe '#self.create' do
    let(:caching) { 'None' }
    let(:use_managed_disks) { true }
    let(:disk_name) { 'fake-disk-name' }
    let(:storage_account_name) { 'fake-storage-account-name' }

    context 'when creating a new disk' do
      let(:id) do
        {
          'disk_name' => disk_name,
          'caching' => caching
        }
      end

      before do
        allow(Bosh::AzureCloud::DiskId).to receive(:_generate_data_disk_name)
          .with(use_managed_disks)
          .and_return(disk_name)
      end

      it 'should generate a disk name and initialize the disk_id' do
        expect do
          disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks)
          expect(disk_id.instance_variable_get('@plain_id')).to eq(nil)
          expect(disk_id.instance_variable_get('@id_hash')).to eq(id)
        end.not_to raise_error
      end
    end

    context 'when use_managed_disks is true' do
      it 'should generate a disk name with prefix bosh-disk-data' do
        disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks, disk_name: nil, storage_account_name: storage_account_name)
        expect(disk_id.disk_name).to start_with('bosh-disk-data')
      end
    end

    context 'when use_managed_disks is false' do
      let(:use_managed_disks) { false }
      it 'should generate a disk name with prefix bosh-data' do
        disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks, disk_name: nil, storage_account_name: storage_account_name)
        expect(disk_id.disk_name).to start_with('bosh-data')
      end
    end

    context 'when creating a new disk with a specified name' do
      let(:id) do
        {
          'disk_name' => disk_name,
          'caching' => caching
        }
      end

      it 'should not generate a disk name and initialize the disk_id' do
        disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks, disk_name: disk_name)
        expect(disk_id.instance_variable_get('@plain_id')).to eq(nil)
        expect(disk_id.instance_variable_get('@id_hash')).to eq(id)
      end
    end

    context 'when resource_group_name is NOT nil' do
      let(:resource_group_name) { 'fake-resource-group-name' }
      let(:id) do
        {
          'disk_name' => disk_name,
          'caching' => caching,
          'resource_group_name' => resource_group_name
        }
      end

      it 'should initialize the disk_id' do
        expect(Bosh::AzureCloud::DiskId).not_to receive(:_generate_data_disk_name)

        disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks, disk_name: disk_name, resource_group_name: resource_group_name)
        expect(disk_id.instance_variable_get('@plain_id')).to eq(nil)
        expect(disk_id.instance_variable_get('@id_hash')).to eq(id)
      end
    end

    context 'when storage_account_name is NOT nil' do
      let(:storage_account_name) { 'fake-storage-account-name' }
      let(:id) do
        {
          'disk_name' => disk_name,
          'caching' => caching,
          'storage_account_name' => storage_account_name
        }
      end

      it 'should initialize the disk_id' do
        expect(Bosh::AzureCloud::DiskId).not_to receive(:_generate_data_disk_name)
        disk_id = Bosh::AzureCloud::DiskId.create(caching, use_managed_disks, disk_name: disk_name, storage_account_name: storage_account_name)
        expect(disk_id.instance_variable_get('@plain_id')).to eq(nil)
        expect(disk_id.instance_variable_get('@id_hash')).to eq(id)
      end
    end
  end

  describe '#self.parse' do
    let(:default_resource_group_name) { 'default-resource-group-name' }

    context 'when id contains ":"' do
      let(:id) { 'a:a;b:b;disk_name:bosh-disk-data-disk-1;caching:c' }
      let(:id_hash) do
        {
          'a' => 'a',
          'b' => 'b',
          'disk_name' => 'bosh-disk-data-disk-1',
          'caching' => 'c',
          'resource_group_name' => default_resource_group_name
        }
      end

      it 'should initialize a v2 disk_id' do
        expect do
          disk_id = Bosh::AzureCloud::CloudIdParser.parse(id, default_resource_group_name)
          expect(disk_id.instance_variable_get('@plain_id')).to eq(nil)
          expect(disk_id.instance_variable_get('@id_hash')).to eq(id_hash)
        end.not_to raise_error
      end
    end

    context 'when id does not contain ":"' do
      let(:id) { 'bosh-disk-data-disk-1' }

      it 'should initialize a v1 disk_id' do
        expect do
          disk_id = Bosh::AzureCloud::CloudIdParser.parse(id, default_resource_group_name)
          expect(disk_id.instance_variable_get('@plain_id')).to eq(id)
        end.not_to raise_error
      end
    end
  end

  describe '#to_s' do
    context 'when disk id is a v1 id' do
      let(:disk_id_string) { 'bosh-disk-data-disk-1' }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'default-resource-group-name') }

      it 'should return the v1 string' do
        expect(disk_id.to_s).to eq(disk_id_string)
      end
    end

    context 'when disk id is a v2 id' do
      context 'when disk id is initialized by self.parse' do
        let(:disk_id_string) { 'caching:c;disk_name:bosh-disk-data-d;resource_group_name:r' }
        let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'r') }

        it 'should return the v2 string' do
          expect(disk_id.to_s).to eq(disk_id_string)
        end
      end

      context 'when disk id is initialized by self.create' do
        let(:caching) { 'None' }
        let(:disk_name) { 'bosh-disk-data-fake-disk-name' }
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:disk_id_string) { "caching:#{caching};disk_name:#{disk_name};resource_group_name:#{resource_group_name}" }
        let(:disk_id) { Bosh::AzureCloud::DiskId.create(caching, true, disk_name: disk_name, resource_group_name: resource_group_name) }

        it 'should return the v2 string' do
          expect(disk_id.to_s).to eq(disk_id_string)
        end
      end

      context 'when the same disk id is initialized by self.create and self.parse' do
        let(:caching) { 'None' }
        let(:disk_name) { 'bosh-disk-data-fake-disk-name' }
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:disk_id_1) { Bosh::AzureCloud::DiskId.create(caching, true, disk_name: disk_name, resource_group_name: resource_group_name) }
        let(:disk_id_2) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_1.to_s, resource_group_name) }

        it 'should have same output string' do
          expect(disk_id_1.to_s).to eq(disk_id_2.to_s)
        end
      end
    end
  end

  describe '#resource_group_name' do
    context 'when disk id is a v1 id' do
      let(:default_resource_group_name) { 'fake-resource-group-name' }
      let(:disk_id_string) { "bosh-disk-data-#{SecureRandom.uuid}-None" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, default_resource_group_name) }

      it 'should return the default resource group' do
        expect(disk_id.resource_group_name).to eq(default_resource_group_name)
      end
    end

    context 'when disk id is a v2 id' do
      context 'when disk id contains resource_group_name' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:disk_id_string) { "disk_name:bosh-disk-data-fake-uuid;caching:None;resource_group_name:#{resource_group_name}" }
        let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

        it 'should return the resource group specified in disk id' do
          expect(disk_id.resource_group_name).to eq(resource_group_name)
        end
      end

      context 'when disk id does not contain resource_group_name' do
        let(:default_resource_group_name) { 'fake-resource-group-name' }
        let(:disk_id_string) { "disk_name:bosh-data-fake-uuid;caching:None;storage_account_name:#{default_resource_group_name}" }
        let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, default_resource_group_name) }

        it 'should return the default resource group' do
          expect(disk_id.resource_group_name).to eq(default_resource_group_name)
        end
      end
    end
  end

  describe '#disk_name' do
    context 'when disk id is a v1 id' do
      let(:disk_id_string) { "bosh-disk-data-#{SecureRandom.uuid}-None" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

      it 'should return v1 id' do
        expect(disk_id.disk_name).to eq(disk_id_string)
      end
    end

    context 'when disk id is a v2 id' do
      context 'when disk_name contains ":"' do
        let(:disk_name) { 'bosh-data-fake-uuid--a:b:c' }
        let(:disk_id_string) { "disk_name:#{disk_name};caching:cc;storage_account_name:ss" }
        let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

        it 'should return the disk name specified in disk id' do
          expect(disk_id.disk_name).to eq(disk_name)
        end
      end

      context 'when disk_name does not contain ":"' do
        let(:disk_name) { 'bosh-disk-data-fake-uuid' }
        let(:disk_id_string) { "disk_name:#{disk_name};caching:cc;resource_group_name:rr" }
        let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

        it 'should return the disk name specified in disk id' do
          expect(disk_id.disk_name).to eq(disk_name)
        end
      end
    end
  end

  describe '#caching' do
    context 'when disk id is a v1 id' do
      let(:caching) { 'None' }
      let(:disk_id_string) { "bosh-disk-data-#{SecureRandom.uuid}-#{caching}" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

      it 'should get caching from v1 disk name' do
        expect(disk_id.caching).to eq(caching)
      end
    end

    context 'when disk id is a v2 id' do
      let(:caching) { 'None' }
      let(:disk_id_string) { "disk_name:bosh-disk-data-uuid;caching:#{caching};resource_group_name:rr" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

      it 'should return caching specified in disk id' do
        expect(disk_id.caching).to eq(caching)
      end
    end

    context 'when disk name does not start with bosh-disk-data or bosh-data' do
      let(:caching) { 'None' }
      let(:disk_name) { 'dd' }
      let(:disk_id) { Bosh::AzureCloud::DiskId.create(caching, true, disk_name: disk_name, resource_group_name: 'rr') }

      it 'should raise an error' do
        expect do
          disk_id.caching
        end.to raise_error /This function should only be called for data disks/
      end
    end
  end

  describe '#storage_account_name' do
    context 'when invalid plain id' do
      let(:caching) { 'None' }
      let(:storage_account_name) { 'fake-storage-account-name' }
      let(:disk_id_string) { "wrongbosh-data-#{storage_account_name}-#{SecureRandom.uuid}-#{caching}" }
      it 'should raise error' do
        expect do
          disk_id = Bosh::AzureCloud::DiskId.create_from_hash({}, disk_id_string)
          disk_id.storage_account_name
        end.to raise_error /Invalid data disk name/
      end
    end

    context 'when disk id is a v1 id' do
      let(:caching) { 'None' }
      let(:storage_account_name) { 'fakestorageaccountname' }
      let(:disk_id_string) { "bosh-data-#{storage_account_name}-#{SecureRandom.uuid}-#{caching}" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

      it 'should get storage account from v1 disk name' do
        expect(disk_id.storage_account_name).to eq(storage_account_name)
      end
    end

    context 'when disk id is a v2 id' do
      let(:storage_account_name) { 'fakestorageaccountname' }
      let(:disk_id_string) { "disk_name:bosh-data-uuid;caching:cc;storage_account_name:#{storage_account_name}" }
      let(:disk_id) { Bosh::AzureCloud::CloudIdParser.parse(disk_id_string, 'fake-resource-group-name') }

      it 'should return the resource group specified in disk id' do
        expect(disk_id.storage_account_name).to eq(storage_account_name)
      end
    end

    context 'when disk name starts with bosh-disk-data (managed)' do
      let(:caching) { 'None' }
      let(:disk_id) { Bosh::AzureCloud::DiskId.create(caching, true, resource_group_name: 'rr') }

      it 'should raise an error' do
        expect do
          disk_id.storage_account_name
        end.to raise_error /This function should only be called for unmanaged disks/
      end
    end
  end

  describe '#validate' do
    context 'disk name' do
      context 'when it is empty' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create('None', true, disk_name: '', resource_group_name: 'r') }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid disk_name in disk id \(version 2\)/
        end
      end
    end

    context 'caching' do
      context 'when it is nil' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create(nil, true, resource_group_name: 'r') }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid caching in disk id \(version 2\)/
        end
      end

      context 'when it is empty' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create('', true, resource_group_name: 'r') }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid caching in disk id \(version 2\)/
        end
      end
    end

    context 'resource_group_name' do
      context 'when it is empty' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create('None', true, resource_group_name: '') }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid resource_group_name in disk id \(version 2\)/
        end
      end
    end

    context 'storage_account_name' do
      context 'when it is nil' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create('None', false) }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid storage_account_name in disk id \(version 2\)/
        end
      end

      context 'when it is empty' do
        let(:disk_id) { Bosh::AzureCloud::DiskId.create('None', false, storage_account_name: '') }

        it 'should raise an error' do
          expect do
            disk_id.validate
          end.to raise_error /Invalid storage_account_name in disk id \(version 2\)/
        end
      end
    end
  end
end
