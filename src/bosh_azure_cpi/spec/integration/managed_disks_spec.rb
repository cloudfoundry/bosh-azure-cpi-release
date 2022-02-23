# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  subject(:cpi_managed) do
    cloud_options_managed = @cloud_options.dup
    cloud_options_managed['azure']['use_managed_disks'] = true
    described_class.new(cloud_options_managed, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
  end

  let(:size) { 10_000 }
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
      @logger.info("Create new managed disk with #{size} MiB")
      disk_cid = cpi_managed.create_disk(size, {})
      expect(disk_cid).not_to be_nil
      @disk_id_pool.push(disk_cid)

      @logger.info("Resize managed disk '#{disk_cid}' to #{new_size} MiB")
      cpi_managed.resize_disk(disk_cid, new_size)

      disk_id_obj = Bosh::AzureCloud::DiskId.parse(disk_cid, @azure_config.resource_group_name)
      disk = get_azure_client.get_managed_disk_by_name(@default_resource_group_name, disk_id_obj.disk_name)
      expect(disk[:disk_size]).to eq(cpi_managed.mib_to_gib(new_size))

      @logger.info("Delete managed disk '#{disk_cid}'")
      cpi_managed.delete_disk(disk_cid)
      @disk_id_pool.delete(disk_cid)
    end
  end
end
