# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    private

    def _build_disks(instance_id, stemcell_info, vm_props)
      if @use_managed_disks
        os_disk = @disk_manager2.os_disk(instance_id.vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ephemeral_disk = @disk_manager2.ephemeral_disk(instance_id.vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
      else
        storage_account_name = instance_id.storage_account_name
        os_disk = @disk_manager.os_disk(storage_account_name, instance_id.vm_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
        ephemeral_disk = @disk_manager.ephemeral_disk(storage_account_name, instance_id.vm_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
      end
      [os_disk, ephemeral_disk]
    end
  end
end
