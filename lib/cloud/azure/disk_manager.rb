module Bosh::AzureCloud
  class DiskManager
    DISK_CONTAINER = 'bosh'

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager)
      @blob_manager = blob_manager
      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(DISK_CONTAINER)
    end

    def delete_disk(disk_name)
      @logger.info("delete_disk(#{disk_name})")
      begin
        @blob_manager.delete_blob(DISK_CONTAINER, "#{disk_name}.vhd")
      rescue => e
        if e.message.include?("BlobNotFound")
          raise Bosh::Clouds::DiskNotFound.new(false), "Disk '#{disk_name}' not found"
        end
      end
    end

    def delete_vm_status_files(prefix)
      @logger.info("delete_vm_status_files(#{prefix})")
      blobs = @blob_manager.list_blobs(DISK_CONTAINER).select{
        |blob| blob.name =~ /status$/ && blob.name.start_with?(prefix)
      }
      blobs.each do |blob|
        @blob_manager.delete_blob(DISK_CONTAINER, blob.name)
      end
    rescue => e
      @logger.warn("delete_vm_status_files - error: #{e.message}")
    end

    def snapshot_disk(disk_name, metadata)
      @logger.info("snapshot_disk(#{disk_name}, #{metadata})")
      snapshot_disk_name = "bosh-disk-#{SecureRandom.uuid}"
      disk_blob_name = "#{disk_name}.vhd"
      @blob_manager.snapshot_blob(DISK_CONTAINER, disk_blob_name, metadata, "#{snapshot_disk_name}.vhd")
      snapshot_disk_name
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [Integer] size disk size in GB
    # @return [String] disk name
    def create_disk(size)
      @logger.info("create_disk(#{size})")
      disk_name = "bosh-disk-#{SecureRandom.uuid}"
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
      disks = @blob_manager.list_blobs(DISK_CONTAINER).select{
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