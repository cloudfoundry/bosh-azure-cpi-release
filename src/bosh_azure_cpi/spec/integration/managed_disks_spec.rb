# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  subject(:cpi_managed) do
    cloud_options_managed = @cloud_options.dup
    cloud_options_managed['azure']['use_managed_disks'] = true
    described_class.new(cloud_options_managed, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  let(:old_size) { 10_000 }
  let(:new_size) { 20_000 }

  before { @disk_id_pool = [] }

  after do
    @disk_id_pool.each do |disk_id|
      @logger.info("Cleanup: Deleting the disk '#{disk_id}'")
      cpi_managed.delete_disk(disk_id) if disk_id
    end
  end

  context 'Resize a disk to a higher size' do
    it 'should work' do
      @logger.info("Create new managed disk with #{old_size} MiB")
      disk_cid = cpi_managed.create_disk(old_size, {})
      expect(disk_cid).not_to be_nil
      @disk_id_pool.push(disk_cid)

      @logger.info("Resize managed disk '#{disk_cid}' to #{new_size} MiB")
      cpi_managed.resize_disk(disk_cid, new_size)

      disk = get_disk(disk_cid)
      expect(disk[:disk_size]).to eq(cpi_managed.mib_to_gib(new_size))

      @logger.info("Delete managed disk '#{disk_cid}'")
      cpi_managed.delete_disk(disk_cid)
      @disk_id_pool.delete(disk_cid)
    end
  end

  describe '#update_disk' do
    context 'When disk properties change on a storage type that does support changing it' do
      let(:old_storage_account_type) { 'Premium_LRS' }
      let(:new_storage_account_type) { 'PremiumV2_LRS' }
      let(:new_iops) { 3500 } # The default value of iops is 3000 for PremiumV2_LRS
      let(:new_mbps) { 125 } # The default value of mbps is 120 for PremiumV2_LRS

      it 'should update the disk properties accordingly' do
        @logger.info("Create a managed disk with #{old_size} MiB")
        disk_cid = cpi_managed.create_disk(old_size, { 'storage_account_type' => old_storage_account_type })
        @disk_id_pool.push(disk_cid) if disk_cid

        @logger.info("Check the disk properties of the created disk '#{disk_cid}'")
        disk = get_disk(disk_cid)
        expect(disk[:disk_size]).not_to eq(cpi_managed.mib_to_gib(new_size))
        expect(disk[:iops]).not_to eq(new_iops)
        expect(disk[:mbps]).not_to eq(new_mbps)
        expect(disk[:sku_name]).to eq(old_storage_account_type)

        @logger.info("Update managed disk '#{disk_cid}' to #{new_size} MiB, iops: #{new_iops}, mbps: #{new_mbps}, storage_account_type: #{new_storage_account_type}")
        cloud_properties = { 'iops' => new_iops, 'mbps' => new_mbps, 'storage_account_type' => new_storage_account_type }
        cpi_managed.update_disk(disk_cid, new_size, cloud_properties)

        @logger.info("Check the disk properties of the updated disk '#{disk_cid}'")
        disk = get_disk(disk_cid)
        expect(disk[:disk_size]).to eq(cpi_managed.mib_to_gib(new_size))
        expect(disk[:iops]).to eq(new_iops)
        expect(disk[:mbps]).to eq(new_mbps)
        expect(disk[:sku_name]).to eq(new_storage_account_type)

        @logger.info("Delete managed disk '#{disk_cid}'")
        cpi_managed.delete_disk(disk_cid)
        @disk_id_pool.delete(disk_cid)
      end
    end

    context 'When disk properties change on a storage type that does not support changing it' do
      let(:old_storage_account_type) { 'Standard_LRS' }
      let(:new_storage_account_type) { 'Premium_LRS' }
      let(:new_iops) { 1000 }
      let(:new_mbps) { 120 }

      it 'raises no error and sets the disk type specific default' do
        @logger.info("Create a managed disk with #{old_size} MiB")
        disk_cid = cpi_managed.create_disk(old_size, { 'storage_account_type' => old_storage_account_type })
        @disk_id_pool.push(disk_cid) if disk_cid

        @logger.info("Check the disk properties of the managed disk '#{disk_cid}'")
        disk = get_disk(disk_cid)
        expect(disk[:sku_name]).to eq(old_storage_account_type)
        expect(disk[:iops]).to eq(500) # iops equals the default value of iops for Standard_LRS
        expect(disk[:mbps]).to eq(60) # mbps equals the default value of mbps for Standard_LRS

        @logger.info("Try to update managed disk '#{disk_cid}' to iops: #{new_iops}, mbps: #{new_mbps}")
        cloud_properties = { 'iops' => new_iops, 'mbps' => new_mbps, 'storage_account_type' => new_storage_account_type }
        expect do
          cpi_managed.update_disk(disk_cid, old_size, cloud_properties)
        end.not_to raise_error

        @logger.info("Check the disk properties of the updated disk '#{disk_cid}'")
        disk = get_disk(disk_cid)
        expect(disk[:sku_name]).to eq(new_storage_account_type)
        expect(disk[:iops]).to eq(120) # iops equals the default value of iops for Premium_LRS
        expect(disk[:mbps]).to eq(25) # mbps equals the default value of mbps for Premium_LRS

        @logger.info("Delete managed disk '#{disk_cid}'")
        cpi_managed.delete_disk(disk_cid)
        @disk_id_pool.delete(disk_cid)
      end
    end
  end

  def get_disk(disk_cid)
    disk_id_obj = Bosh::AzureCloud::DiskId.parse(disk_cid, @azure_config.resource_group_name)
    get_azure_client.get_managed_disk_by_name(@default_resource_group_name, disk_id_obj.disk_name)
  end
end
