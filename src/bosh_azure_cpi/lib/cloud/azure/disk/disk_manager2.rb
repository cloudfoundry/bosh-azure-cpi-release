# frozen_string_literal: true

module Bosh::AzureCloud
  class DiskManager2
    include Bosh::Exec
    include Helpers

    attr_accessor :vm_props

    def initialize(azure_client)
      @azure_client = azure_client
      @logger = Bosh::Clouds::Config.logger
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [string]  disk_id               instance of DiskId
    # @param [string]  location              location of the disk
    # @param [Integer] size                  disk size in GiB
    # @param [string]  storage_account_type  the storage account type. Possible values: Standard_LRS or Premium_LRS.
    # When disk is in an availability zone
    # @param [String] zone                   Zone number in string. Possible values: "1", "2" or "3".
    #
    # @return [void]
    def create_disk(disk_id, location, size, storage_account_type, zone = nil)
      @logger.info("create_disk(#{disk_id}, #{location}, #{size}, #{storage_account_type}, #{zone})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name
      caching = disk_id.caching
      tags = AZURE_TAGS.merge(
        'caching' => caching
      )
      disk_params = {
        name: disk_name,
        location: location,
        tags: tags,
        disk_size: size,
        account_type: storage_account_type
      }

      disk_params[:zone] = zone unless zone.nil?

      @logger.info("Start to create an empty managed disk '#{disk_name}' in resource group '#{resource_group_name}'")
      @azure_client.create_empty_managed_disk(resource_group_name, disk_params)
    end

    def create_disk_from_blob(disk_id, blob_uri, location, storage_account_type, zone = nil)
      @logger.info("create_disk_from_blob(#{disk_id}, #{blob_uri}, #{location}, #{storage_account_type}, #{zone})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name
      caching = disk_id.caching
      tags = AZURE_TAGS.merge(
        'caching' => caching,
        'original_blob' => blob_uri
      )
      disk_params = {
        name: disk_name,
        location: location,
        tags: tags,
        source_uri: blob_uri,
        account_type: storage_account_type,
        zone: zone
      }
      @logger.info("Start to create a managed disk '#{disk_name}' in resource group '#{resource_group_name}' from the source uri '#{blob_uri}'")
      @azure_client.create_managed_disk_from_blob(resource_group_name, disk_params)
    end

    def delete_disk(resource_group_name, disk_name)
      @logger.info("delete_disk(#{resource_group_name}, #{disk_name})")
      retried = false
      begin
        @azure_client.delete_managed_disk(resource_group_name, disk_name) if _has_disk?(resource_group_name, disk_name)
      rescue Bosh::AzureCloud::AzureConflictError => e
        # Workaround: Do one retry for AzureConflictError, and give up if it still fails.
        #             After Managed Disks add "retry-after" in the response header,
        #             the workaround can be removed because the retry in azure_client will be triggered.
        unless retried
          @logger.debug("delete_disk: Received an AzureConflictError: '#{e.inspect}', retrying.")
          retried = true
          retry
        end
        @logger.error('delete_disk: Retry still fails due to AzureConflictError, giving up')
        raise e
      end
    end

    def delete_data_disk(disk_id)
      @logger.info("delete_data_disk(#{disk_id})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name
      delete_disk(resource_group_name, disk_name)
    end

    def has_data_disk?(disk_id)
      @logger.info("has_data_disk?(#{disk_id})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name
      _has_disk?(resource_group_name, disk_name)
    end

    def get_data_disk(disk_id)
      @logger.info("get_data_disk(#{disk_id})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name
      _get_disk(resource_group_name, disk_name)
    end

    def snapshot_disk(snapshot_id, disk_name, metadata)
      @logger.info("snapshot_disk(#{snapshot_id}, #{disk_name}, #{metadata})")
      resource_group_name = snapshot_id.resource_group_name()
      snapshot_name = snapshot_id.disk_name
      snapshot_params = {
        name: snapshot_name,
        tags: metadata.merge(
          'original' => disk_name
        ),
        disk_name: disk_name
      }
      @logger.info("Start to create a snapshot '#{snapshot_name}' from a managed disk '#{disk_name}'")
      @azure_client.create_managed_snapshot(resource_group_name, snapshot_params)
    end

    def delete_snapshot(snapshot_id)
      @logger.info("delete_snapshot(#{snapshot_id})")
      resource_group_name = snapshot_id.resource_group_name()
      snapshot_name = snapshot_id.disk_name
      @azure_client.delete_managed_snapshot(resource_group_name, snapshot_name)
    end

    def has_snapshot?(resource_group_name, snapshot_name)
      @logger.info("has_snapshot?(#{resource_group_name}, #{snapshot_name})")
      snapshot = @azure_client.get_managed_snapshot_by_name(resource_group_name, snapshot_name)
      !snapshot.nil?
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
      disk_caching = @vm_props.caching
      validate_disk_caching(disk_caching)

      root_disk_size = @vm_props.root_disk.fetch('size', nil)
      use_root_disk_for_ephemeral_data = @vm_props.ephemeral_disk.fetch('use_root_disk', false)
      disk_size = get_os_disk_size(root_disk_size, stemcell_info, use_root_disk_for_ephemeral_data)

      {
        disk_name: generate_os_disk_name(vm_name),
        disk_size: disk_size,
        disk_caching: disk_caching
      }
    end

    def ephemeral_disk(vm_name)
      ephemeral_disk = @vm_props.ephemeral_disk
      use_root_disk = ephemeral_disk.fetch('use_root_disk', false)
      return nil if use_root_disk

      disk_info = DiskInfo.for(@vm_props.instance_type)
      disk_size = disk_info.size
      size = ephemeral_disk.fetch('size', nil)
      unless size.nil?
        validate_disk_size(size)
        disk_size = size / 1024
      end

      {
        disk_name: generate_ephemeral_disk_name(vm_name),
        disk_size: disk_size,
        disk_caching: 'ReadWrite'
      }
    end

    def migrate_to_zone(disk_id, disk, zone)
      @logger.info("migrate_to_zone(#{disk_id}, #{disk}, #{zone})")
      resource_group_name = disk_id.resource_group_name
      disk_name = disk_id.disk_name

      snapshot_id = DiskId.create(disk_id.caching, true, resource_group_name: resource_group_name)
      snapshot_name = snapshot_id.disk_name
      snapshot_disk(snapshot_id, disk_name, {})
      @logger.info("Snapshot #{snapshot_name} is created for disk #{disk_name} for migration purpose")

      if has_snapshot?(resource_group_name, snapshot_name)
        delete_disk(resource_group_name, disk_name)
      else
        error_message = "migrate_to_zone - Can'n find snapshot '#{snapshot_name}' in resource group '#{resource_group_name}', abort migration.\n"
        error_message += "You need to migrate '#{disk_id}' to zone '#{zone}' manually."
        raise Bosh::Clouds::CloudError, error_message
      end

      disk_params = {
        name: disk_name,
        location: disk[:location],
        zone: zone,
        account_type: disk[:account_type],
        tags: disk[:tags]
      }

      max_retries = 2
      retry_count = 0
      begin
        @azure_client.create_managed_disk_from_snapshot(resource_group_name, disk_params, snapshot_name)
      rescue StandardError => e
        if retry_count < max_retries
          @logger.info("migrate_to_zone - Got error when creating '#{disk_name}' from snapshot '#{snapshot_name}': \n#{e.inspect}\n#{e.backtrace.join('\n')}. \nRetry #{retry_count}: will retry to create the disk.")
          retry_count += 1
          retry
        end

        error_message = "migrate_to_zone - Failed to create disk '#{disk_name}' from snapshot '#{snapshot_name}' in resource group '#{resource_group_name}'.\n"
        error_message += "You need to recover '#{disk_id}' mannually from snapshot '#{snapshot_name}' and put it in zone '#{zone}'. Try:\n"
        error_message += "    'az disk create --resource-group #{resource_group_name} --location #{disk[:location]} --sku #{disk[:account_type]} --zone #{zone} --name #{disk_name} --source #{snapshot_name}'\n"
        error_message += "#{e.inspect}\n#{e.backtrace.join("\n")}"
        raise Bosh::Clouds::CloudError, error_message
      end

      if has_data_disk?(disk_id)
        delete_snapshot(snapshot_id)
        @logger.info("Disk '#{disk_name}' has migrated to zone '#{zone}'")
      else
        error_message = "migrate_to_zone - Can'n find disk '#{disk_name}' in resource group '#{resource_group_name}' after migration.\n"
        error_message += "You need to recover '#{disk_id}' manually from snapshot '#{snapshot_name}' and put it in zone '#{zone}'. Try:\n"
        error_message += "    'az disk create --resource-group #{resource_group_name} --location #{disk[:location]} --sku #{disk[:account_type]} --zone #{zone} --name #{disk_name} --source #{snapshot_name}'\n"
        raise Bosh::Clouds::CloudError, error_message
      end
    end

    private

    def _get_disk(resource_group_name, disk_name)
      @logger.info("_get_disk(#{resource_group_name}, #{disk_name})")
      disk = @azure_client.get_managed_disk_by_name(resource_group_name, disk_name)
    end

    def _has_disk?(resource_group_name, disk_name)
      @logger.info("_has_disk?(#{resource_group_name}, #{disk_name})")
      disk = _get_disk(resource_group_name, disk_name)
      !disk.nil?
    end
  end
end
