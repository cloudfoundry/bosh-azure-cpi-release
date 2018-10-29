# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManagerBase
    include Helpers

    def get_storage_account_from_vm_properties(vm_properties)
      CPILogger.instance.logger.debug("get_storage_account_from_vm_properties(#{vm_properties})")

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
          CPILogger.instance.logger.debug("get_storage_account_from_vm_properties - Picking one available storage account by pattern '#{pattern}', max disk number '#{storage_account_max_disk_number}'")

          # Remove * in the pattern
          pattern = pattern[1..-2]
          storage_accounts = @azure_client.list_storage_accounts.select { |s| s[:name] =~ /^.*#{pattern}.*$/ }
          CPILogger.instance.logger.debug("get_storage_account_from_vm_properties - Pick all storage accounts by pattern:\n#{storage_accounts.inspect}")

          result = []
          # Randomaly pick one storage account
          storage_accounts.shuffle!
          storage_accounts.each do |storage_account|
            disks = @disk_manager.list_disks(storage_account[:name])
            if disks.size <= storage_account_max_disk_number
              CPILogger.instance.logger.debug("get_storage_account_from_vm_properties - Pick the available storage account '#{storage_account[:name]}', current disk numbers: '#{disks.size}'")
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
          # Create the storage account automatically if the storage account in vm_types or vm_extensions does not exist
          storage_account = @storage_account_manager.get_or_create_storage_account(storage_account_name, {}, storage_account_type, storage_account_kind, vm_properties.location, [DISK_CONTAINER, STEMCELL_CONTAINER], false)
        end
      else
        storage_account_name = @storage_account_manager.default_storage_account_name
      end

      CPILogger.instance.logger.debug("get_storage_account_from_vm_properties: use the storage account '#{storage_account_name}'")
      storage_account = @azure_client.get_storage_account_by_name(storage_account_name) if storage_account.nil?
      storage_account
    end

    protected

    def initialize(use_managed_disks, azure_client, stemcell_manager, stemcell_manager2, light_stemcell_manager)
      @use_managed_disks = use_managed_disks
      @azure_client = azure_client
      @stemcell_manager = stemcell_manager
      @stemcell_manager2 = stemcell_manager2
      @light_stemcell_manager = light_stemcell_manager
    end

    def _get_network_security_group(vm_props, network)
      # Network security group name can be specified in vm_types or vm_extensions, networks and global configuration (ordered by priority)
      network_security_group_cfg = vm_props.security_group.name.nil? ? network.security_group : vm_props.security_group
      network_security_group_cfg = @azure_config.default_security_group if network_security_group_cfg.name.nil?
      return nil if network_security_group_cfg.name.nil?

      cloud_error('Cannot specify an empty string to the network security group') if network_security_group_cfg.name.empty?

      unless network_security_group_cfg.resource_group_name.nil?
        network_security_group = @azure_client.get_network_security_group_by_name(
          network_security_group_cfg.resource_group_name,
          network_security_group_cfg.name
        )
        cloud_error("Cannot found the security group: #{network_security_group_cfg.name} in the specified resource group: #{network_security_group_cfg.resource_group_name}") if network_security_group.nil?
        return network_security_group
      end

      resource_group_name = network.resource_group_name

      # The resource group which the NSG belongs to can be specified in networks and global configuration (ordered by priority)
      network_security_group = @azure_client.get_network_security_group_by_name(
        resource_group_name,
        network_security_group_cfg.name
      )

      # network.resource_group_name may return the default resource group name in global configurations. See network.rb.
      default_resource_group_name = @azure_config.resource_group_name
      if network_security_group.nil? && resource_group_name != default_resource_group_name
        CPILogger.instance.logger.info("Cannot find the network security group '#{network_security_group_cfg.name}' in the resource group '#{resource_group_name}', trying to search it in the default resource group '#{default_resource_group_name}'")
        network_security_group = @azure_client.get_network_security_group_by_name(default_resource_group_name, network_security_group_cfg.name)
      end

      cloud_error("Cannot find the network security group '#{network_security_group_cfg.name}'") if network_security_group.nil?
      network_security_group
    end

    def _ensure_resource_group_exists(resource_group_name, location)
      resource_group = @azure_client.get_resource_group(resource_group_name)
      return true unless resource_group.nil?

      # If resource group does not exist, create it
      @azure_client.create_resource_group(resource_group_name, location)
    end

    def _get_stemcell_info(stemcell_cid, vm_props, storage_account_name)
      stemcell_info = nil
      if @use_managed_disks
        if is_light_stemcell_cid?(stemcell_cid)
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell '#{stemcell_cid}' does not exist" unless @light_stemcell_manager.has_stemcell?(vm_props.location, stemcell_cid)

          stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_cid)
        else
          begin
            storage_account_type = _get_root_disk_type(vm_props)
            # Treat user_image_info as stemcell_info
            stemcell_info = @stemcell_manager2.get_user_image_info(stemcell_cid, storage_account_type, vm_props.location)
          rescue StandardError => e
            raise Bosh::Clouds::VMCreationFailed.new(false), "Failed to get the user image information for the stemcell '#{stemcell_cid}': #{e.inspect}\n#{e.backtrace.join("\n")}"
          end
        end
      elsif is_light_stemcell_cid?(stemcell_cid)
        raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell '#{stemcell_cid}' does not exist" unless @light_stemcell_manager.has_stemcell?(vm_props.location, stemcell_cid)

        stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_cid)
      else
        raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell '#{stemcell_cid}' does not exist" unless @stemcell_manager.has_stemcell?(storage_account_name, stemcell_cid)

        stemcell_info = @stemcell_manager.get_stemcell_info(storage_account_name, stemcell_cid)
      end

      CPILogger.instance.logger.debug("get_stemcell_info - got stemcell '#{stemcell_info.inspect}'")
      stemcell_info
    end

    def _get_network_subnet(network)
      subnet = @azure_client.get_network_subnet_by_name(network.resource_group_name, network.virtual_network_name, network.subnet_name)
      cloud_error("Cannot find the subnet '#{network.virtual_network_name}/#{network.subnet_name}' in the resource group '#{network.resource_group_name}'") if subnet.nil?
      subnet
    end

    def _get_disk_params(disk_id, use_managed_disks)
      disk_name = disk_id.disk_name
      if use_managed_disks
        {
          disk_name: disk_name,
          caching: disk_id.caching,
          disk_bosh_id: disk_id.to_s,
          disk_id: @azure_client.get_managed_disk_by_name(disk_id.resource_group_name, disk_name)[:id],
          managed: true
        }
      else
        {
          disk_name: disk_name,
          caching: disk_id.caching,
          disk_bosh_id: disk_id.to_s,
          disk_uri: @disk_manager.get_data_disk_uri(disk_id),
          disk_size: @disk_manager.get_disk_size_in_gb(disk_id),
          managed: false
        }
      end
    end

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
