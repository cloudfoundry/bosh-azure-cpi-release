module Bosh::AzureCloud
  class DiskManager
    DISK_FAMILY = 'bosh'

    attr_reader   :container_name
    attr_accessor :logger

    include Bosh::Exec
    include Helpers

    def initialize(container_name, storage_manager, blob_manager)
      @container_name = container_name
      @storage_manager = storage_manager
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def has_disk?(disk_id)
      (!find(disk_id).nil?)
    end

    def find(disk_name)
      logger.info("Start to find disk: disk_name: #{disk_name}")

      disk = nil
      begin
        response = handle_response http_get("/services/disks/#{disk_name}")
        info = response.css('Disk')
        disk = {
          :affinity_group => xml_content(info, 'AffinityGroup'),
          :logical_size_in_gb => xml_content(info, 'LogicalSizeInGB'),
          :media_link => xml_content(info, 'MediaLink'),
          :name => xml_content(info, 'Name')
        }
      rescue => e
        logger.debug("Failed to find disk: #{e.message}\n#{e.backtrace.join("\n")}")
      end
      disk
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [Integer] size disk size in GB
    # @return [String] disk name
    def create_disk(size)
      disk_name = "bosh-disk-#{SecureRandom.uuid}"
      logger.info("Start to create disk: disk_name: #{disk_name}")

      logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(container_name, "#{disk_name}.vhd", size)

      begin
        logger.info("Start to create an disk with created VHD")
        handle_response http_post("/services/disks",
                             "<Disk xmlns=\"http://schemas.microsoft.com/windowsazure\" " \
                             "xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" \
                             '<OS>Linux</OS>' \
                             "<Label>#{DISK_FAMILY}</Label>" \
                             "<MediaLink>#{@storage_manager.get_storage_blob_endpoint}#{container_name}/#{disk_name}.vhd</MediaLink>" \
                             "<Name>#{disk_name}</Name>" \
                             '</Disk>')
        disk_name
      rescue => e
        @blob_manager.delete_blob(container_name, "#{disk_name}.vhd")
        cloud_error("Failed to create disk: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def delete_disk(disk_name)
      logger.info("Start to delete disk: disk_name: #{disk_name}")

      begin
        http_delete("/services/disks/#{disk_name}?comp=media")
      rescue => e
        cloud_error("Failed to delete_disk: #{e.message}\n#{e.backtrace.join("\n")}")
      end
      nil
    end

    def snapshot_disk(disk_id, metadata)
      snapshot_disk_name = "bosh-disk-#{SecureRandom.uuid}"

      logger.info("Start to take the snapshot for the blob of the disk #{disk_id}")
      disk = find(disk_id)
      logger.info("Get the media link of the disk: #{disk[:media_link]}")

      blob_info = disk[:media_link].split('/')
      blob_container_name = blob_info[3]
      disk_blob_name = blob_info[4]
      @blob_manager.snapshot_blob(blob_container_name, disk_blob_name, metadata, "#{snapshot_disk_name}.vhd")

      begin
        logger.info("Start to create an disk with the snapshot blob")
        blob_info[4] = "#{snapshot_disk_name}.vhd"
        handle_response http_post("/services/disks",
                             "<Disk xmlns=\"http://schemas.microsoft.com/windowsazure\" " \
                             "xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" \
                             '<OS>Linux</OS>' \
                             "<Label>#{DISK_FAMILY}</Label>" \
                             "<MediaLink>#{blob_info.join('/')}</MediaLink>" \
                             "<Name>#{snapshot_disk_name}</Name>" \
                             '</Disk>')
        snapshot_disk_name
      rescue => e
        @blob_manager.delete_blob(blob_container_name, "#{snapshot_disk_name}.vhd")
        cloud_error("Failed to create disk: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def disks
      logger.info("Start to list disks")

      disks = []
      storage_affinity_group = @storage_manager.get_storage_affinity_group

      response = handle_response http_get("/services/disks")
      response.css('Disks Disk').each do |disk_info|
        affinity_group = xml_content(disk_info, 'AffinityGroup')
        if affinity_group == storage_affinity_group
          disk = {
            :affinity_group => affinity_group,
            :logical_size_in_gb => xml_content(disk_info, 'LogicalDiskSizeInGB'),
            :media_link => xml_content(disk_info, 'MediaLink'),
            :name => xml_content(disk_info, 'Name'),
            :attached => false
          }

          unless xml_content(disk_info.css('AttachedTo'), 'HostedServiceName').empty?
            disk[:attached] = true
            disk[:attached_to] = {
              :hosted_service_name => xml_content(disk_info.css('AttachedTo'), 'HostedServiceName'),
              :deployment_name => xml_content(disk_info.css('AttachedTo'), 'DeploymentName'),
              :role_name => xml_content(disk_info.css('AttachedTo'), 'RoleName')
            }
          end

          disks << disk
        end
      end
      disks
    rescue => e
      cloud_error("Failed to list disks: #{e.message}\n#{e.backtrace.join("\n")}")
    end
  end
end
