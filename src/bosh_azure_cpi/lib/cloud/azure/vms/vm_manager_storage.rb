# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    # This function is not idempotent, make sure it is not called more than once
    def get_storage_account_from_vm_properties(vm_properties, location)
      @logger.debug("get_storage_account_from_vm_properties(#{vm_properties}, #{location})")

      # If storage_account_name is not specified in vm_types or vm_extensions, use the default storage account in global configurations
      storage_account_name = nil
      if !vm_properties.storage_account_name.nil?
        storage_account_name = vm_properties.storage_account_name
        storage_account_type = vm_properties.storage_account_type
        storage_account_kind = vm_properties.storage_account_kind
        # Create the storage account automatically if the storage account in vm_types or vm_extensions does not exist
        storage_account = @storage_account_manager.get_or_create_storage_account(storage_account_name, {}, storage_account_type, storage_account_kind, location, [DISK_CONTAINER, STEMCELL_CONTAINER], false)
      else
        storage_account_name = @storage_account_manager.default_storage_account_name
      end

      @logger.debug("get_storage_account_from_vm_properties: use the storage account '#{storage_account_name}'")
      storage_account = @azure_client.get_storage_account_by_name(storage_account_name) if storage_account.nil?
      storage_account
    end
  end
end
