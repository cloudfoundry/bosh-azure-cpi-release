# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::DiskId do
  describe '#self.parse' do
    let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:uuid) { SecureRandom.uuid.to_s }
    let(:caching) { 'ReadOnly' }

    context 'when id_str is v1 format' do
      context 'with unmanaged disks' do
        let(:storage_account_name) { '6slyzrx7ypji2cfdefaultsa' } # There should be no "-" in the storage account name
        context 'when the id is disk id' do
          let(:id_str) { "bosh-data-#{storage_account_name}-#{uuid}-#{caching}" }
          it 'should return a correct disk id' do
            disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
            expect(disk_id.disk_name).to eq(id_str)
            expect(disk_id.caching).to eq(caching)
            expect(disk_id.storage_account_name).to eq(storage_account_name)
            expect(disk_id.resource_group_name).to eq(default_resource_group_name)
            expect(disk_id.to_s).to eq(id_str)
          end
        end

        context 'when the id is snapshot id' do
          let(:id_str) { "bosh-data-#{storage_account_name}-#{uuid}-#{caching}--snapshottime" }
          it 'should return a correct snapshot id' do
            snapshot_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
            expect(snapshot_id.disk_name).to eq(id_str)
            expect(snapshot_id.to_s).to eq(id_str)
          end
        end
      end

      context 'with managed disks' do
        let(:id_str) { "bosh-disk-data-#{uuid}-#{caching}" }
        it 'should return a correct disk id' do
          disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
          expect(disk_id.disk_name).to eq(id_str)
          expect(disk_id.caching).to eq(caching)
          expect(disk_id.resource_group_name).to eq(default_resource_group_name)
          expect do
            disk_id.storage_account_name
          end.to raise_error /This function should only be called for unmanaged disks/
          expect(disk_id.to_s).to eq(id_str)
        end
      end
    end

    context 'when id_str is v2 format' do
      context 'with unmanaged disks' do
        let(:storage_account_name) { '6slyzrx7ypji2cfdefaultsa' } # There should be no "-" in the storage account name
        context 'without resource_group_name' do
          context 'when the id is disk id' do
            let(:disk_name) { "bosh-data-#{uuid}" }
            let(:id_str) { "caching:#{caching};disk_name:#{disk_name};storage_account_name:#{storage_account_name}" }
            it 'should return a correct disk id' do
              disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
              expect(disk_id.disk_name).to eq(disk_name)
              expect(disk_id.caching).to eq(caching)
              expect(disk_id.storage_account_name).to eq(storage_account_name)
              expect(disk_id.resource_group_name).to eq(default_resource_group_name)
              expect(disk_id.to_s).to eq("caching:#{caching};disk_name:#{disk_name};resource_group_name:#{default_resource_group_name};storage_account_name:#{storage_account_name}")
            end
          end

          context 'when the id is snapshot id' do
            let(:snapshot_disk_name) { "bosh-data-#{uuid}--snapshottime" }
            let(:id_str) { "caching:#{caching};disk_name:#{snapshot_disk_name};storage_account_name:#{storage_account_name}" }
            it 'should return a correct snapshot id' do
              snapshot_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
              expect(snapshot_id.disk_name).to eq(snapshot_disk_name)
              expect(snapshot_id.to_s).to eq("caching:#{caching};disk_name:#{snapshot_disk_name};resource_group_name:#{default_resource_group_name};storage_account_name:#{storage_account_name}")
            end
          end
        end

        context 'with resource_group_name' do
          let(:disk_name) { "bosh-data-#{uuid}" }
          let(:rg_name) { 'another-resource-group-name' }
          let(:id_str) { "caching:#{caching};disk_name:#{disk_name};resource_group_name:#{rg_name};storage_account_name:#{storage_account_name}" }
          it 'should return a correct disk id' do
            disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
            expect(disk_id.disk_name).to eq(disk_name)
            expect(disk_id.caching).to eq(caching)
            expect(disk_id.storage_account_name).to eq(storage_account_name)
            expect(disk_id.resource_group_name).to eq(rg_name)
            expect(disk_id.to_s).to eq(id_str)
          end
        end
      end

      context 'with managed disks' do
        let(:disk_name) { "bosh-disk-data-#{uuid}" }
        context 'with resource_group_name is default_resource_group_name' do
          let(:id_str) { "caching:#{caching};disk_name:#{disk_name};resource_group_name:#{default_resource_group_name}" }
          it 'should return a correct disk id' do
            disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
            expect(disk_id.disk_name).to eq(disk_name)
            expect(disk_id.caching).to eq(caching)
            expect(disk_id.resource_group_name).to eq(default_resource_group_name)
            expect do
              disk_id.storage_account_name
            end.to raise_error /This function should only be called for unmanaged disks/
            expect(disk_id.to_s).to eq(id_str)
          end
        end

        context 'with resource_group_name is not default_resource_group_name' do
          let(:rg_name) { 'another-resource-group-name' }
          let(:id_str) { "caching:#{caching};disk_name:#{disk_name};resource_group_name:#{rg_name}" }
          it 'should return a correct disk id' do
            disk_id = Bosh::AzureCloud::DiskId.parse(id_str, default_resource_group_name)
            expect(disk_id.disk_name).to eq(disk_name)
            expect(disk_id.caching).to eq(caching)
            expect(disk_id.resource_group_name).to eq(rg_name)
            expect do
              disk_id.storage_account_name
            end.to raise_error /This function should only be called for unmanaged disks/
            expect(disk_id.to_s).to eq(id_str)
          end
        end
      end
    end
  end
end
