# frozen_string_literal: true

module Bosh::AzureCloud
  class DiskManager
    include Bosh::Exec
    include Helpers

    def initialize(azure_config, blob_manager)
      @azure_config = azure_config
      @blob_manager = blob_manager
    end

    def delete_disk(storage_account_name, disk_name)
      CPILogger.instance.logger.info("delete_disk(#{storage_account_name}, #{disk_name})")
      @blob_manager.delete_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd") if _has_disk?(storage_account_name, disk_name)
    end

    def delete_data_disk(disk_id)
      CPILogger.instance.logger.info("delete_data_disk(#{disk_id})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      delete_disk(storage_account_name, disk_name)
    end

    def delete_vm_status_files(storage_account_name, prefix)
      CPILogger.instance.logger.info("delete_vm_status_files(#{storage_account_name}, #{prefix})")
      blobs = @blob_manager.list_blobs(storage_account_name, DISK_CONTAINER, prefix).select do |blob|
        blob.name =~ /status$/
      end
      blobs.each do |blob|
        @blob_manager.delete_blob(storage_account_name, DISK_CONTAINER, blob.name)
      end
    rescue StandardError => e
      CPILogger.instance.logger.debug("delete_vm_status_files - error: #{e.inspect}\n#{e.backtrace.join("\n")}")
    end

    def snapshot_disk(storage_account_name, disk_name, metadata)
      CPILogger.instance.logger.info("snapshot_disk(#{storage_account_name}, #{disk_name}, #{metadata})")
      snapshot_time = @blob_manager.snapshot_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", metadata)

      _generate_snapshot_name(disk_name, snapshot_time)
    end

    def delete_snapshot(snapshot_id)
      CPILogger.instance.logger.info("delete_snapshot(#{snapshot_id})")
      storage_account_name = snapshot_id.storage_account_name
      snapshot_name = snapshot_id.disk_name
      disk_name, snapshot_time = _parse_snapshot_name(snapshot_name)
      @blob_manager.delete_blob_snapshot(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", snapshot_time)
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [String]  disk_id           - instance of DiskId
    # @param [Integer] size              - disk size in GiB
    #
    # @return [void]
    def create_disk(disk_id, size)
      CPILogger.instance.logger.info("create_disk(#{disk_id}, #{size})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      CPILogger.instance.logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", size)
    end

    def has_data_disk?(disk_id)
      CPILogger.instance.logger.info("has_data_disk?(#{disk_id})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      _has_disk?(storage_account_name, disk_name)
    end

    def is_migrated?(disk_id)
      CPILogger.instance.logger.info("is_migrated?(#{disk_id})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      return false unless _has_disk?(storage_account_name, disk_name)

      metadata = @blob_manager.get_blob_metadata(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd")
      (METADATA_FOR_MIGRATED_BLOB_DISK.to_a - metadata.to_a).empty?
    end

    def get_disk_uri(storage_account_name, disk_name)
      CPILogger.instance.logger.info("get_disk_uri(#{storage_account_name}, #{disk_name})")
      @blob_manager.get_blob_uri(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd")
    end

    def get_data_disk_uri(disk_id)
      CPILogger.instance.logger.info("get_data_disk_uri(#{disk_id})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      get_disk_uri(storage_account_name, disk_name)
    end

    def get_disk_size_in_gb(disk_id)
      CPILogger.instance.logger.info("get_disk_size_in_gb(#{disk_id})")
      storage_account_name = disk_id.storage_account_name
      disk_name = disk_id.disk_name
      @blob_manager.get_blob_size_in_bytes(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd") / 1024 / 1024 / 1024
    end

    # bosh-os-[VM-NAME]
    def generate_os_disk_name(vm_name)
      "#{OS_DISK_PREFIX}-#{vm_name}"
    end

    # bosh-os-[VM-NAME]-ephemeral
    def generate_ephemeral_disk_name(vm_name)
      "#{OS_DISK_PREFIX}-#{vm_name}-#{EPHEMERAL_DISK_POSTFIX}"
    end

    def os_disk(storage_account_name, vm_name, stemcell_info, size, caching, use_root_disk_as_ephemeral)
      disk_name = generate_os_disk_name(vm_name)
      disk_uri = get_disk_uri(storage_account_name, disk_name)
      validate_disk_caching(caching)

      disk_size = get_os_disk_size(size, stemcell_info, use_root_disk_as_ephemeral)

      {
        disk_name: disk_name,
        disk_uri: disk_uri,
        disk_size: disk_size,
        disk_caching: caching
      }
    end

    def ephemeral_disk(storage_account_name, vm_name, instance_type, size, use_root_disk_as_ephemeral)
      return nil if use_root_disk_as_ephemeral

      disk_info = DiskInfo.for(instance_type)
      disk_size = disk_info.size
      unless size.nil?
        validate_disk_size(size)
        disk_size = size / 1024
      end

      {
        disk_name: EPHEMERAL_DISK_POSTFIX,
        disk_uri: get_disk_uri(storage_account_name, generate_ephemeral_disk_name(vm_name)),
        disk_size: disk_size,
        disk_caching: 'ReadWrite'
      }
    end

    def list_disks(storage_account_name)
      CPILogger.instance.logger.info("list_disks(#{storage_account_name})")
      disks = []
      blobs = @blob_manager.list_blobs(storage_account_name, DISK_CONTAINER).select do |blob|
        blob.name =~ /vhd$/
      end
      blobs.each do |blob|
        disk = {
          disk_name: blob.name[0..-5]
        }
        disks << disk
      end
      disks
    end

    private

    def _has_disk?(storage_account_name, disk_name)
      CPILogger.instance.logger.info("_has_disk?(#{storage_account_name}, #{disk_name})")
      blob_properties = @blob_manager.get_blob_properties(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd")
      !blob_properties.nil?
    end

    # bosh-data-STORAGEACCOUNTNAME-UUID-CACHING--SNAPSHOTTIME
    def _generate_snapshot_name(disk_name, snapshot_time)
      "#{disk_name}--#{snapshot_time}"
    end

    def _parse_snapshot_name(snapshot_name)
      ret = snapshot_name.match('^(.*)--(.*)$')
      cloud_error("Invalid snapshot id #{snapshot_name}") if ret.nil?
      [ret[1], ret[2]]
    end
  end
end
