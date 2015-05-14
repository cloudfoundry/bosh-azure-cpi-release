module Bosh::AzureCloud
  class DiskManager
    attr_reader   :container_name
    attr_accessor :logger
    
    include Bosh::Exec
    include Helpers

    def initialize(container_name, blob_manager)
      @container_name = container_name
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def delete_disk(disk_name)
      @logger.info("delete_disk(#{disk_name})")
      @blob_manager.delete_blob(container_name, "#{disk_name}.vhd")
    end

    def snapshot_disk(disk_name, metadata)
      @logger.info("snapshot_disk(#{disk_name}, #{metadata})")
      snapshot_disk_name = "bosh-disk-#{SecureRandom.uuid}"
      disk_blob_name = "#{disk_name}.vhd"
      @blob_manager.snapshot_blob(container_name, disk_blob_name, metadata, "#{snapshot_disk_name}.vhd")
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
      logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(container_name, "#{disk_name}.vhd", size)
      disk_name
    end

    def has_disk?(disk_name)
      @logger.info("has_disk?(#{disk_name})")
      @blob_manager.blob_exist?(container_name, "#{disk_name}.vhd")
    end

    def get_disk_uri(disk_name)
      @logger.info("get_disk_uri(#{disk_name})")
      @blob_manager.get_blob_uri(@container_name, "#{disk_name}.vhd")
    end

    def get_new_os_disk_uri(instance_id)
      @logger.info("get_new_os_disk_uri(#{instance_id})")
      os_disk_name = get_os_disk_name(instance_id)
      @blob_manager.get_blob_uri(@container_name, "#{os_disk_name}.vhd")
    end

    def disks
      @logger.info("disks")
      disks = @blob_manager.list_blobs(@container_name).select{
        |d| return d.name = ~/vhd$/
      }.map { |d|
        return {
            :name     => d.name,
            :attached => d.properties[:lease_status] == 'unlocked' ? false : true
         }
      }
      disks
    end

  end
end