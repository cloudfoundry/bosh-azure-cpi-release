module Bosh::AzureCloud
  class DiskManager
    OS_DISK_PREFIX         = 'bosh-os'
    DATA_DISK_PREFIX       = 'bosh-data'
    EPHEMERAL_DISK_POSTFIX = 'ephemeral'

    include Bosh::Exec
    include Helpers

    attr_writer :resource_pool

    def initialize(azure_properties, blob_manager)
      @azure_properties = azure_properties
      @blob_manager = blob_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def delete_disk(disk_name)
      @logger.info("delete_disk(#{disk_name})")
      storage_account_name = get_storage_account_name(disk_name)
      @blob_manager.delete_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd") if has_disk?(disk_name)
    end

    def delete_vm_status_files(storage_account_name, prefix)
      @logger.info("delete_vm_status_files(#{storage_account_name}, #{prefix})")
      blobs = @blob_manager.list_blobs(storage_account_name, DISK_CONTAINER, prefix).select{
        |blob| blob.name =~ /status$/
      }
      blobs.each do |blob|
        @blob_manager.delete_blob(storage_account_name, DISK_CONTAINER, blob.name)
      end
    rescue => e
      @logger.debug("delete_vm_status_files - error: #{e.inspect}\n#{e.backtrace.join("\n")}")
    end

    def snapshot_disk(disk_name, metadata)
      @logger.info("snapshot_disk(#{disk_name}, #{metadata})")
      storage_account_name = get_storage_account_name(disk_name)
      snapshot_time = @blob_manager.snapshot_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", metadata)

      generate_snapshot_id(disk_name, snapshot_time)
    end

    def delete_snapshot(snapshot_id)
      @logger.info("delete_snapshot(#{snapshot_id})")
      disk_name, snapshot_time = parse_snapshot_id(snapshot_id)
      storage_account_name = get_storage_account_name(disk_name)
      @blob_manager.delete_blob_snapshot(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", snapshot_time)
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [string] storage_account_name the storage account where the disk is created
    # @param [Integer] size disk size in GiB
    # @param [Hash] cloud_properties cloud properties to create the disk
    # @return [String] disk name
    def create_disk(storage_account_name, size, cloud_properties)
      @logger.info("create_disk(#{storage_account_name}, #{size}, #{cloud_properties})")
      caching = 'None'
      if !cloud_properties.nil? && !cloud_properties['caching'].nil?
        caching = cloud_properties['caching']
        validate_disk_caching(caching)
      end
      disk_name = generate_data_disk_name(storage_account_name, caching)
      @logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", size)
      disk_name
    end

    def has_disk?(disk_name)
      @logger.info("has_disk?(#{disk_name})")
      storage_account_name = get_storage_account_name(disk_name)
      blob_properties = @blob_manager.get_blob_properties(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd")
      !blob_properties.nil?
    end

    def get_disk_uri(disk_name)
      @logger.info("get_disk_uri(#{disk_name})")
      storage_account_name = get_storage_account_name(disk_name)
      @blob_manager.get_blob_uri(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd")
    end

    def get_data_disk_caching(disk_name)
      @logger.info("get_data_disk_caching(#{disk_name})")
      storage_account_name, caching = parse_data_disk_name(disk_name)
      caching
    end

    # bosh-os-STORAGEACCOUNTNAME-AGENTID
    def generate_os_disk_name(instance_id)
      "#{OS_DISK_PREFIX}-#{instance_id}"
    end

    # bosh-os-STORAGEACCOUNTNAME-AGENTID-ephemeral
    def generate_ephemeral_disk_name(instance_id)
      "#{OS_DISK_PREFIX}-#{instance_id}-#{EPHEMERAL_DISK_POSTFIX}"
    end

    def os_disk(instance_id)
      disk_name = generate_os_disk_name(instance_id)
      disk_uri = get_disk_uri(disk_name)

      disk_size = nil
      root_disk = @resource_pool.fetch('root_disk', {})
      size = root_disk.fetch('size', nil)
      unless size.nil?
        validate_disk_size(size)
        disk_size = size/1024
        cloud_error('root_disk.size must not be smaller than 3 GiB') if disk_size < 3
      end

      disk_caching = @resource_pool.fetch('caching', 'ReadWrite')
      validate_disk_caching(disk_caching)

      # The default OS disk size depends on the size of the VHD in the stemcell which is 3 GiB for now.
      # When using OS disk to store the ephemeral data and root_disk.size is not set, resize it to 30 GiB.
      if disk_size.nil? && ephemeral_disk(instance_id).nil?
        disk_size = 30
      end

      return {
        :disk_name    => disk_name,
        :disk_uri     => disk_uri,
        :disk_size    => disk_size,
        :disk_caching => disk_caching
      }
    end

    def ephemeral_disk(instance_id)
      ephemeral_disk = @resource_pool.fetch('ephemeral_disk', {})
      use_root_disk = ephemeral_disk.fetch('use_root_disk', false)
      return nil if use_root_disk

      disk_info = DiskInfo.for(@resource_pool['instance_type'])
      disk_size = disk_info.size
      size = ephemeral_disk.fetch('size', nil)
      unless size.nil?
        validate_disk_size(size)
        disk_size = size/1024
      end

      return {
        :disk_name    => EPHEMERAL_DISK_NAME,
        :disk_uri     => get_disk_uri(generate_ephemeral_disk_name(instance_id)),
        :disk_size    => disk_size,
        :disk_caching => 'ReadWrite'
      }
    end

    def list_disks(storage_account_name)
      @logger.info("list_disks(#{storage_account_name})")
      disks = []
      blobs = @blob_manager.list_blobs(storage_account_name, DISK_CONTAINER).select{
        |blob| blob.name =~ /vhd$/
      }
      blobs.each do |blob|
        disk = {
          :disk_name => blob.name[0..-5]
        }
        disks << disk
      end
      disks
    end

    private

    def parse_os_disk_name(disk_name)
      # For backwards compatibility
      # Use default storage account name if the disk name does not contain a storage account name
      storage_account_name = @azure_properties['storage_account_name']

      ret = disk_name.match("^#{OS_DISK_PREFIX}-([^-]*)-(.*)$")
      unless ret.nil?
        storage_account_name = ret[1]
      end
      storage_account_name
    end

    def parse_data_disk_name(disk_name)
      # For backwards compatibility
      # Use default storage account name if the disk name does not contain a storage account name
      storage_account_name = @azure_properties['storage_account_name']
      caching              = 'None'

      ret = disk_name.match("^#{DATA_DISK_PREFIX}-([^-]*)-(.*)-([^-]*)$")
      unless ret.nil?
        storage_account_name = ret[1]
        caching              = ret[3]
      end
      return storage_account_name, caching
    end

    # bosh-data-STORAGEACCOUNTNAME-UUID-CACHING
    def generate_data_disk_name(storage_account_name, caching)
      "#{DATA_DISK_PREFIX}-#{storage_account_name}-#{SecureRandom.uuid}-#{caching}"
    end

    def get_storage_account_name(disk_name)
      if disk_name.start_with?(OS_DISK_PREFIX)
        parse_os_disk_name(disk_name)
      elsif disk_name.start_with?(DATA_DISK_PREFIX)
        storage_account_name, caching = parse_data_disk_name(disk_name)
        storage_account_name
      else
        cloud_error("Invalid disk name #{disk_name}")
      end
    end

    # bosh-data-STORAGEACCOUNTNAME-UUID-CACHING--SNAPSHOTTIME
    def generate_snapshot_id(disk_name, snapshot_time)
      "#{disk_name}--#{snapshot_time}"
    end

    def parse_snapshot_id(snapshot_id)
      ret = snapshot_id.match("^(.*)--(.*)$")
      cloud_error("Invalid snapshot id #{snapshot_id}") if ret.nil?
      return ret[1], ret[2]
    end
  end
end
