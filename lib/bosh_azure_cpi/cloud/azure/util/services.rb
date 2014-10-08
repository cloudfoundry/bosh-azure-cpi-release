require_relative '../vm_manager'
require_relative '../affinity_group_manager'
require_relative '../virtual_network_manager'
require_relative '../stemcell_manager'
require_relative '../storage_account_manager'
require_relative '../blob_manager'


module Bosh::AzureCloud::Util
  module Services

    def instance_manager
      @instance_manager ||= VMManager.new(azure_vm_client, image_service, vnet_manager, storage_manager)
    end

    def affinity_group_manager
      @ag_manager ||= AffinityGroupManager.new(base_service)
    end

    def vnet_manager
      @vnet_manager ||= VirtualNetworkManager.new(vnet_service, affinity_group_manager)
    end

    def stemcell_manager
      @stemcell_creator ||= StemcellManager.new(blob_manager, image_service)
    end

    def storage_manager
      storage_acct_name = options['azure']['storage_account_name'] || raise("Missing 'storage_account_name' from manifest")
      @storage_manager ||= StorageAccountManager.new(storage_service, storage_acct_name)
    end

    def blob_manager
      @blob_manager ||= BlobManager.new(blob_service)
    end

    def cloud_service_service
      @cloud_service_service ||= Azure::CloudServiceManagement::CloudServiceManagementService.new
    end

    def azure_vm_client
      @azure_vm_client ||= Azure::VirtualMachineManagementService.new
    end

    def base_service
      @base_service ||= Azure::BaseManagementService.new
    end

    def image_service
      @image_service ||= Azure::VirtualMachineImageManagementService.new
    end

    def vnet_service
      @vnet_service ||= Azure::VirtualNetworkManagementService.new
    end

    def vdisk_service
      @vdisk_service ||= Azure::VirtualMachineImageManagement::VirtualMachineDiskManagementService.new
    end

    def storage_service
      @storage_service ||= Azure::StorageManagement::StorageManagementService.new
    end

    def blob_service
      @blob_service ||= Azure::BlobService.new
    end
  end
end