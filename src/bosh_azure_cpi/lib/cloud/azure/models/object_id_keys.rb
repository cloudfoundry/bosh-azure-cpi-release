# frozen_string_literal: true

module Bosh::AzureCloud
  module ObjectIDKeys
    # Common
    STORAGE_ACCOUNT_NAME_KEY = 'storage_account_name'

    # Common VM
    AGENT_ID_KEY = 'agent_id'

    # Disk
    CACHING_KEY = 'caching'
    DISK_NAME_KEY = 'disk_name'

    # VMSS
    VMSS_NAME_KEY = 'vmss_name'
    VMSS_INSTANCE_ID_KEY = 'vmss_instance_id'

    # Types
    DISK_ID_TYPE = 'disk_id'
    VM_ID_TYPE = 'vm_id'
    VMMS_ID_TYPE = 'vmss_id'
  end
end
