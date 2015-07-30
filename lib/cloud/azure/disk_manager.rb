module Bosh::AzureCloud
  class DiskManager
    DISK_CONTAINER = 'bosh'
    DISK_PREFIX    = 'bosh-disk'

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager)
      @blob_manager = blob_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def create_container()
      unless @blob_manager.container_exist?(DISK_CONTAINER)
        @blob_manager.create_container(DISK_CONTAINER)
      end
    end

    def delete_disk(disk_name)
      @logger.info("delete_disk(#{disk_name})")
      @blob_manager.delete_blob(DISK_CONTAINER, "#{disk_name}.vhd") if has_disk?(disk_name)
    end

    def delete_vm_status_files(prefix)
      @logger.info("delete_vm_status_files(#{prefix})")
      blobs = @blob_manager.list_blobs(DISK_CONTAINER, prefix).select{
        |blob| blob.name =~ /status$/
      }
      blobs.each do |blob|
        @blob_manager.delete_blob(DISK_CONTAINER, blob.name)
      end
    rescue => e
      @logger.debug("delete_vm_status_files - error: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def snapshot_disk(disk_name, metadata)
      @logger.info("snapshot_disk(#{disk_name}, #{metadata})")
      snapshot_disk_name = "#{DISK_PREFIX}-#{SecureRandom.uuid}_snapshot"
      @blob_manager.snapshot_blob(DISK_CONTAINER, "#{disk_name}.vhd", metadata, "#{snapshot_disk_name}.vhd")
      snapshot_disk_name
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [Integer] size disk size in GB
    # @return [String] disk name
    def create_disk(size)
      @logger.info("create_disk(#{size})")
      create_container()
      disk_name = "#{DISK_PREFIX}-#{SecureRandom.uuid}"
      @logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(DISK_CONTAINER, "#{disk_name}.vhd", size)
      disk_name
    end

    def has_disk?(disk_name)
      @logger.info("has_disk?(#{disk_name})")
      @blob_manager.blob_exist?(DISK_CONTAINER, "#{disk_name}.vhd")
    end

    def get_disk_uri(disk_name)
      @logger.info("get_disk_uri(#{disk_name})")
      @blob_manager.get_blob_uri(DISK_CONTAINER, "#{disk_name}.vhd")
    end

    def disks
      @logger.info("disks")
      disks = @blob_manager.list_blobs(DISK_CONTAINER, DISK_PREFIX).select{
        |blob| blob.name =~ /vhd$/
      }.map { |blob|
        {
            :name     => blob.name,
            :attached => blob.properties[:lease_status] == 'unlocked' ? false : true
         }
      }
      disks
    end
  end
end