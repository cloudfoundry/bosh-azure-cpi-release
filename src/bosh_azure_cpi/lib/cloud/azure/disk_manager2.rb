module Bosh::AzureCloud
  class DiskManager2
    include Bosh::Exec
    include Helpers

    attr_accessor :resource_pool

    def initialize(azure_client2)
      @azure_client2 = azure_client2
      @logger = Bosh::Clouds::Config.logger
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [string]  disk_id               instance of DiskId
    # @param [string]  location              location of the disk
    # @param [Integer] size                  disk size in GiB
    # @param [string]  storage_account_type  the storage account type. Possible values: Standard_LRS or Premium_LRS.
    #
    # @return [void]
    def create_disk(disk_id, location, size, storage_account_type)
      @logger.info("create_disk(#{disk_id}, #{location}, #{size}, #{storage_account_type})")
      resource_group_name = disk_id.resource_group_name()
      disk_name = disk_id.disk_name()
      caching = disk_id.caching()
      tags = AZURE_TAGS.merge({
        "caching" => caching
      })
      disk_params = {
        :name => disk_name,
        :location => location,
        :tags => tags,
        :disk_size => size,
        :account_type => storage_account_type
      }
      @logger.info("Start to create an empty managed disk `#{disk_name}' in resource group `#{resource_group_name}'")
      @azure_client2.create_empty_managed_disk(resource_group_name, disk_params)
    end

    def create_disk_from_blob(disk_id, blob_uri, location, storage_account_type)
      @logger.info("create_disk_from_blob(#{disk_id}, #{blob_uri}, #{location}, #{storage_account_type})")
      resource_group_name = disk_id.resource_group_name()
      disk_name = disk_id.disk_name()
      caching = disk_id.caching()
      tags = AZURE_TAGS.merge({
        "caching" => caching,
        "original_blob" => blob_uri
      })
      disk_params = {
        :name => disk_name,
        :location => location,
        :tags => tags,
        :source_uri => blob_uri,
        :account_type => storage_account_type
      }
      @logger.info("Start to create a managed disk `#{disk_name}' in resource group `#{resource_group_name}' from the source uri `#{blob_uri}'")
      @azure_client2.create_managed_disk_from_blob(resource_group_name, disk_params)
    end

    def delete_disk(resource_group_name, disk_name)
      @logger.info("delete_disk(#{resource_group_name}, #{disk_name})")
      retried = false
      begin
        @azure_client2.delete_managed_disk(resource_group_name, disk_name) if has_disk?(resource_group_name, disk_name)
      rescue Bosh::AzureCloud::AzureConflictError => e
        # Workaround: Do one retry for AzureConflictError, and give up if it still fails.
        #             After Managed Disks add "retry-after" in the response header,
        #             the workaround can be removed because the retry in azure_client2 will be triggered.
        unless retried
          @logger.debug("delete_disk: Received an AzureConflictError: `#{e.inspect}', retrying.")
          retried = true
          retry
        end
        @logger.error("delete_disk: Retry still fails due to AzureConflictError, giving up")
        raise e
      end
    end

    def delete_data_disk(disk_id)
      @logger.info("delete_data_disk(#{disk_id})")
      resource_group_name = disk_id.resource_group_name()
      disk_name = disk_id.disk_name()
      delete_disk(resource_group_name, disk_name)
    end

    def has_disk?(resource_group_name, disk_name)
      @logger.info("has_disk?(#{resource_group_name}, #{disk_name})")
      disk = get_disk(resource_group_name, disk_name)
      !disk.nil?
    end

    def has_data_disk?(disk_id)
      @logger.info("has_data_disk?(#{disk_id})")
      resource_group_name = disk_id.resource_group_name()
      disk_name = disk_id.disk_name()
      has_disk?(resource_group_name, disk_name)
    end

    def get_disk(resource_group_name, disk_name)
      @logger.info("get_disk(#{resource_group_name}, #{disk_name})")
      disk = @azure_client2.get_managed_disk_by_name(resource_group_name, disk_name)
    end

    def get_data_disk(disk_id)
      @logger.info("get_data_disk(#{disk_id})")
      resource_group_name = disk_id.resource_group_name()
      disk_name = disk_id.disk_name()
      get_disk(resource_group_name, disk_name)
    end

    def snapshot_disk(snapshot_id, disk_name, metadata)
      @logger.info("snapshot_disk(#{snapshot_id}, #{disk_name}, #{metadata})")
      resource_group_name = snapshot_id.resource_group_name()
      snapshot_name = snapshot_id.disk_name()
      snapshot_params = {
        :name => snapshot_name,
        :tags => metadata.merge({
          "original" => disk_name
        }),
        :disk_name => disk_name
      }
      @logger.info("Start to create a snapshot `#{snapshot_name}' from a managed disk `#{disk_name}'")
      @azure_client2.create_managed_snapshot(resource_group_name, snapshot_params)
    end

    def delete_snapshot(snapshot_id)
      @logger.info("delete_snapshot(#{snapshot_id})")
      resource_group_name = snapshot_id.resource_group_name()
      snapshot_name = snapshot_id.disk_name()
      @azure_client2.delete_managed_snapshot(resource_group_name, snapshot_name)
    end

    # bosh-disk-os-[VM-NAME]
    def generate_os_disk_name(vm_name)
      "#{MANAGED_OS_DISK_PREFIX}-#{vm_name}"
    end

    # bosh-disk-os-[VM-NAME]-ephemeral
    def generate_ephemeral_disk_name(vm_name)
      "#{MANAGED_OS_DISK_PREFIX}-#{vm_name}-#{EPHEMERAL_DISK_POSTFIX}"
    end

    def os_disk(vm_name, stemcell_info)
      disk_caching = @resource_pool.fetch('caching', 'ReadWrite')
      validate_disk_caching(disk_caching)

      root_disk_size = @resource_pool.fetch('root_disk', {}).fetch('size', nil)
      use_root_disk_for_ephemeral_data = @resource_pool.fetch('ephemeral_disk', {}).fetch('use_root_disk', false)
      disk_size = get_os_disk_size(root_disk_size, stemcell_info, use_root_disk_for_ephemeral_data)

      return {
        :disk_name    => generate_os_disk_name(vm_name),
        :disk_size    => disk_size,
        :disk_caching => disk_caching
      }
    end

    def ephemeral_disk(vm_name)
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
        :disk_name    => generate_ephemeral_disk_name(vm_name),
        :disk_size    => disk_size,
        :disk_caching => 'ReadWrite'
      }
    end
  end
end
