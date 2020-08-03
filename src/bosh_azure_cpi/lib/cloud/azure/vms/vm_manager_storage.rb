# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    # This function is not idempotent, make sure it is not called more than once
    def get_storage_account_from_vm_properties(vm_properties, location)
      @logger.debug("get_storage_account_from_vm_properties(#{vm_properties}, #{location})")

      # If storage_account_name is not specified in vm_types or vm_extensions, use the default storage account in global configurations
      storage_account_name = nil
      if !vm_properties.storage_account_name.nil?
        if vm_properties.storage_account_name.include?('*')
          ret = vm_properties.storage_account_name.match('^\*{1}[a-z0-9]+\*{1}$')
          cloud_error("get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid. It should be '*keyword*' (keyword only contains numbers and lower-case letters) if it is a pattern.") if ret.nil?

          # Users could use *xxx* as the pattern
          # Users could specify the maximum disk numbers storage_account_max_disk_number in one storage account. Default is 30.
          # CPI uses the pattern to filter all storage accounts under the default resource group and
          # then randomly select an available storage account in which the disk numbers under the container 'bosh'
          # is not more than the limitation.
          pattern = vm_properties.storage_account_name
          storage_account_max_disk_number = vm_properties.storage_account_max_disk_number
          @logger.debug("get_storage_account_from_vm_properties - Picking one available storage account by pattern '#{pattern}', max disk number '#{storage_account_max_disk_number}'")

          # Remove * in the pattern
          pattern = pattern[1..-2]
          storage_accounts = @azure_client.list_storage_accounts.select { |s| s[:name] =~ /^.*#{pattern}.*$/ }
          @logger.debug("get_storage_account_from_vm_properties - Pick all storage accounts by pattern:\n#{storage_accounts.inspect}")

          result = []
          # Randomaly pick one storage account
          storage_accounts.shuffle!
          storage_accounts.each do |storage_account|
            disks = @disk_manager.list_disks(storage_account[:name])
            if disks.size <= storage_account_max_disk_number
              @logger.debug("get_storage_account_from_vm_properties - Pick the available storage account '#{storage_account[:name]}', current disk numbers: '#{disks.size}'")
              return storage_account
            else
              result << {
                name: storage_account[:name],
                disk_count: disks.size
              }
            end
          end

          cloud_error("get_storage_account_from_vm_properties - Cannot find an available storage account.\n#{result.inspect}")
        else
          storage_account_name = vm_properties.storage_account_name
          storage_account_type = vm_properties.storage_account_type
          storage_account_kind = vm_properties.storage_account_kind
          storage_https_traffic = vm_properties.storage_https_traffic
          # Create the storage account automatically if the storage account in vm_types or vm_extensions does not exist
          storage_account = @storage_account_manager.get_or_create_storage_account(storage_account_name, {}, storage_account_type, storage_account_kind, location, [DISK_CONTAINER, STEMCELL_CONTAINER], false, storage_https_traffic)
        end
      else
        storage_account_name = @storage_account_manager.default_storage_account_name
      end

      @logger.debug("get_storage_account_from_vm_properties: use the storage account '#{storage_account_name}'")
      storage_account = @azure_client.get_storage_account_by_name(storage_account_name) if storage_account.nil?
      storage_account
    end
  end
end
