# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    private

    def _build_disks(instance_id, stemcell_info, vm_props)
      if @use_managed_disks
        os_disk = @disk_manager2.os_disk(instance_id.vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ephemeral_disk = @disk_manager2.ephemeral_disk(instance_id.vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
      else
        storage_account_name = instance_id.storage_account_name
        os_disk = @disk_manager.os_disk(storage_account_name, instance_id.vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ephemeral_disk = @disk_manager.ephemeral_disk(storage_account_name, instance_id.vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
      end
      [os_disk, ephemeral_disk]
    end

    def _get_root_disk_type(vm_props)
      storage_account_type = get_storage_account_type_by_instance_type(vm_props.instance_type)
      storage_account_type = vm_props.storage_account_type unless vm_props.storage_account_type.nil?
      storage_account_type = vm_props.root_disk.type unless vm_props.root_disk.type.nil?
      storage_account_type
    end
  end
end
