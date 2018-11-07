# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManagerAdaptive < VMManagerBase
    def initialize(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager, config_disk_manager)
      @azure_config = azure_config
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @disk_manager2 = disk_manager2
      @azure_client = azure_client
      @storage_account_manager = storage_account_manager
      @stemcell_manager = stemcell_manager
      @stemcell_manager2 = stemcell_manager2
      @light_stemcell_manager = light_stemcell_manager
      @config_disk_manager = config_disk_manager

      @vmss_manager = VMSSManager.new(@azure_config, @registry_endpoint, @disk_manager, @disk_manager2, @azure_client, @storage_account_manager, @stemcell_manager, @stemcell_manager2, @light_stemcell_manager, @config_disk_manager)
      @vm_manager = VMManager.new(@azure_config, @registry_endpoint, @disk_manager, @disk_manager2, @azure_client, @storage_account_manager, @stemcell_manager, @stemcell_manager2, @light_stemcell_manager)
    end

    def create(bosh_vm_meta, vm_props, disk_cids, network_configurator, env)
      # choose the normal vm manager or vmss manager according to the parameters
      use_vmss = @azure_config.vmss.enabled
      # vmss does not support static private ip.
      networks = network_configurator.networks
      networks.each_with_index do |network, _|
        use_vmss = false if network.is_a?(ManualNetwork)
      end

      use_vmss = false unless @azure_config.use_managed_disks
      if use_vmss
        @vmss_manager.create(bosh_vm_meta, vm_props, network_configurator, env)
      else
        @vm_manager.create(bosh_vm_meta, vm_props, disk_cids, network_configurator, env)
      end
    end

    def find(instance_id)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.find(instance_id)
      else
        @vm_manager.find(instance_id)
      end
    end

    def delete(instance_id)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.delete(instance_id)
      else
        @vm_manager.delete(instance_id)
      end
    end

    def reboot(instance_id)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.reboot(instance_id)
      else
        @vm_manager.reboot(instance_id)
      end
    end

    def set_metadata(instance_id, metadata)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.set_metadata(instance_id, metadata)
      else
        @vm_manager.set_metadata(instance_id, metadata)
      end
    end

    ##
    # Attach a disk to the Vm
    #
    # @param [InstanceId] instance_id Instance id
    # @param [DiskId] disk_id disk id
    # @return [String] lun
    def attach_disk(instance_id, disk_id)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.attach_disk(instance_id, disk_id)
      else
        @vm_manager.attach_disk(instance_id, disk_id)
      end
    end

    def detach_disk(instance_id, disk_id)
      if instance_id.is_a?(VMSSInstanceId)
        @vmss_manager.detach_disk(instance_id, disk_id)
      else
        @vm_manager.detach_disk(instance_id, disk_id)
      end
    end
  end
end
