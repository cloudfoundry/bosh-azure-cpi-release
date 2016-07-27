module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_reader   :registry
    attr_reader   :options
    # Below defines are for test purpose
    attr_reader   :azure_client2, :blob_manager, :table_manager, :storage_account_manager
    attr_reader   :disk_manager, :disk_manager2, :stemcell_manager, :stemcell_manager2, :light_stemcell_manager

    include Helpers

    ##
    # Cloud initialization
    #
    # @param [Hash] options cloud options
    def initialize(options)
      @options = options.dup.freeze

      @logger = Bosh::Clouds::Config.logger

      @use_managed_disks = azure_properties['use_managed_disks']

      init_registry
      init_azure
    end

    ##
    # Creates a stemcell
    #
    # @param [String] image_path path to an opaque blob containing the stemcell image
    # @param [Hash] stemcell_properties properties required for creating this template
    #               specific to a CPI
    # @return [String] opaque id later used by {#create_vm} and {#delete_stemcell}
    def create_stemcell(image_path, stemcell_properties)
      with_thread_name("create_stemcell(#{image_path}, #{stemcell_properties})") do
        if has_light_stemcell_property?(stemcell_properties)
          @light_stemcell_manager.create_stemcell(stemcell_properties)
        elsif @use_managed_disks
          @stemcell_manager2.create_stemcell(image_path, stemcell_properties)
        else
          @stemcell_manager.create_stemcell(image_path, stemcell_properties)
        end
      end
    end

    ##
    # Deletes a stemcell
    #
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @return [void]
    def delete_stemcell(stemcell_id)
      with_thread_name("delete_stemcell(#{stemcell_id})") do
        if is_light_stemcell_id?(stemcell_id)
          @light_stemcell_manager.delete_stemcell(stemcell_id)
        elsif @use_managed_disks
          @stemcell_manager2.delete_stemcell(stemcell_id)
        else
          @stemcell_manager.delete_stemcell(stemcell_id)
        end
      end
    end

    ##
    # Creates a VM - creates (and powers on) a VM from a stemcell with the proper resources
    # and on the specified network. When disk locality is present the VM will be placed near
    # the provided disk so it won't have to move when the disk is attached later.
    #
    # Sample networking config:
    #  {"network_a" =>
    #    {
    #      "netmask"          => "255.255.248.0",
    #      "ip"               => "172.30.41.40",
    #      "gateway"          => "172.30.40.1",
    #      "dns"              => ["172.30.22.153", "172.30.22.154"],
    #      "default"          => ["dns", "gateway"],
    #      "cloud_properties" => {"virtual_network_name"=>"boshvnet", "subnet_name"=>"BOSH"}
    #    }
    #  }
    #
    # Sample resource pool config (CPI specific):
    #  {"instance_type" => "Standard_D1"}
    #  {
    #    "instance_type" => "Standard_D1",
    #    # storage_account_name may not exist. The default storage account will be used.
    #    # storage_account_name may be a complete name. It will be used to create the VM.
    #    # storage_account_name may be a pattern '*xxx*'. CPI will filter all storage accounts under the resource group
    #      by the pattern and pick one storage account which has less than 30 disks to create the VM.
    #    "storage_account_name" => "xxx",
    #    "storage_account_type" => "Standard_LRS",
    #    "storage_account_max_disk_number" => 30,
    #    "availability_set" => "DEA_set",
    #    "platform_update_domain_count" => 5,
    #    "platform_fault_domain_count" => 3,
    #    "security_group" => "nsg-bosh",
    #    "root_disk" => {
    #      "size" => 50120, # disk size in MiB
    #    },
    #    "ephemeral_disk" => {
    #      "use_root_disk" => false, # Whether to use OS disk to store the ephemeral data
    #      "size" => 30720, # disk size in MiB
    #    },
    #    "assign_dynamic_public_ip": true
    #  }
    #
    # Sample env config:
    #  {
    #    "bosh" => {
    #      "group" => "group"
    #    }
    #  }
    #
    # @param [String] agent_id UUID for the agent that will be used later on by the director
    #                 to locate and talk to the agent
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @param [Hash] resource_pool cloud specific properties describing the resources needed
    #               for this VM
    # @param [Hash] networks list of networks and their settings needed for this VM
    # @param [optional, String, Array] disk_locality disk name(s) if known of the disk(s) that will be
    #                                    attached to this vm
    # @param [optional, Hash] env environment that will be passed to this vm
    # @return [String] opaque id later used by {#configure_networks}, {#attach_disk},
    #                  {#detach_disk}, and {#delete_vm}
    def create_vm(agent_id, stemcell_id, resource_pool, networks, disk_locality = nil, env = nil)
      @logger.info("create_vm(#{agent_id}, #{stemcell_id}, #{resource_pool}, #{networks}, #{disk_locality}, #{env})")
      with_thread_name("create_vm(#{agent_id}, ...)") do
        if @use_managed_disks
          instance_id = agent_id
          storage_account_type = resource_pool['storage_account_type']
          storage_account_type = get_storage_account_type_by_instance_type(resource_pool['instance_type']) if storage_account_type.nil?
          if !resource_pool['storage_account_location'].nil?
            location = resource_pool['storage_account_location'] 
          else
            location = @azure_client2.get_resource_group()[:location]
          end

          if is_light_stemcell_id?(stemcell_id)
            raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist" unless @light_stemcell_manager.has_stemcell?(location, stemcell_id)
            stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_id)
          else
            begin
              # Treat user_image_info as stemcell_info
              stemcell_info = @stemcell_manager2.get_user_image_info(stemcell_id, storage_account_type, location)
            rescue => e
              raise Bosh::Clouds::VMCreationFailed.new(false), "Failed to get the user image information for the stemcell `#{stemcell_id}': #{e.inspect}\n#{e.backtrace.join("\n")}"
            end
          end
        else
          storage_account = @storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
          location = storage_account[:location]

          if is_light_stemcell_id?(stemcell_id)
            raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist" unless @light_stemcell_manager.has_stemcell?(location, stemcell_id)
            stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_id)
          else
            unless @stemcell_manager.has_stemcell?(storage_account[:name], stemcell_id)
              raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist"
            end
            stemcell_info = @stemcell_manager.get_stemcell_info(storage_account[:name], stemcell_id)
          end

          instance_id = "#{storage_account[:name]}-#{agent_id}"
        end

        if stemcell_info.is_windows?
          cloud_error("Currently Azure CPI only supports to create Windows VMs with managed disks. Supporting Windows VMs without managed disks is coming soon.") unless @use_managed_disks

          # Windows VM name can't be longer than 15 characters, regenerate instance_id
          instance_id = generate_unique_id(WINDOWS_VM_NAME_LENGTH)
        end

        vm_params = @vm_manager.create(
          instance_id,
          location,
          stemcell_info,
          resource_pool,
          NetworkConfigurator.new(azure_properties, networks),
          env)

        @logger.info("Created new vm `#{instance_id}'")

        begin
          registry_settings = initial_agent_settings(
            agent_id,
            networks,
            env,
            vm_params
          )
          registry.update_settings(instance_id, registry_settings)

          instance_id
        rescue => e
          @logger.error(%Q[Failed to update registry after new vm was created: #{e.inspect}\n#{e.backtrace.join("\n")}])
          @vm_manager.delete(instance_id)
          raise e
        end
      end
    end

    ##
    # Deletes a VM
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @return [void]
    def delete_vm(instance_id)
      with_thread_name("delete_vm(#{instance_id})") do
        @logger.info("Deleting instance `#{instance_id}'")
        @vm_manager.delete(instance_id)
      end
    end

    ##
    # Checks if a VM exists
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @return [Boolean] True if the vm exists
    def has_vm?(instance_id)
      with_thread_name("has_vm?(#{instance_id})") do
        vm = @vm_manager.find(instance_id)
        !vm.nil? && vm[:provisioning_state] != 'Deleting'
      end
    end

    ##
    # Checks if a disk exists
    #
    # @param [String] disk disk_id that was once returned by {#create_disk}
    # @return [Boolean] True if the disk exists
    def has_disk?(disk_id)
      with_thread_name("has_disk?(#{disk_id})") do
        if @use_managed_disks
          return true if @disk_manager2.has_disk?(disk_id)
          return false if @disk_manager.is_migrated?(disk_id)
        end
        @disk_manager.has_disk?(disk_id)
      end
    end

    ##
    # Reboots a VM
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Optional, Hash] options CPI specific options (e.g hard/soft reboot)
    # @return [void]
    def reboot_vm(instance_id, options = nil)
      with_thread_name("reboot_vm(#{instance_id}, #{options})") do
        @vm_manager.reboot(instance_id)
      end
    end

    ##
    # Set metadata for a VM
    #
    # Optional. Implement to provide more information for the IaaS.
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Hash] metadata metadata key/value pairs
    # @return [void]
    def set_vm_metadata(instance_id, metadata)
      @logger.info("set_vm_metadata(#{instance_id}, #{metadata})")
      @vm_manager.set_metadata(instance_id, encode_metadata(metadata))
    end

    ##
    # Configures networking an existing VM.
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Hash] networks list of networks and their settings needed for this VM,
    #               same as the networks argument in {#create_vm}
    # @return [void]
    def configure_networks(instance_id, networks)
      @logger.info("configure_networks(#{instance_id}, #{networks})")
      # Azure does not support to configure the network of an existing VM,
      # so we need to notify the InstanceUpdater to recreate it
      raise Bosh::Clouds::NotSupported
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM. When
    # VM locality is specified the disk will be placed near the VM so it won't have to move
    # when it's attached later.
    #
    # @param [Integer] size disk size in MiB
    # @param [Hash] cloud_properties properties required for creating this disk
    #               specific to a CPI
    # @param [optional, String] instance_id vm id if known of the VM that this disk will
    #                           be attached to
    #
    # ==== cloud_properties
    # [optional, String] caching the disk caching type. It can be either None, ReadOnly or ReadWrite.
    #                            Default is None. Only None and ReadOnly are supported for premium disks.
    # [optional, String] storage_account_type the storage account type. For blob disks, it can be either
    #                    Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS or Premium_LRS.
    #                    For managed disks, it can only be Standard_LRS or Premium_LRS.
    #
    # @return [String] opaque id later used by {#attach_disk}, {#detach_disk}, and {#delete_disk}
    def create_disk(size, cloud_properties, instance_id = nil)
      with_thread_name("create_disk(#{size}, #{cloud_properties})") do
        validate_disk_size(size)
        disk_id = nil
        if @use_managed_disks
          if instance_id.nil?
            # If instance_id is nil, the managed disk will be created in the resource group location.
            resource_group = @azure_client2.get_resource_group()
            location = resource_group[:location]
            default_storage_account_type = STORAGE_ACCOUNT_TYPE_STANDARD_LRS
          else
            cloud_error("Cannot create a managed disk for a VM with unmanaged disks") unless is_managed_vm?(instance_id)
            # If the instance is a managed VM, the managed disk will be created in the location of the VM.
            vm = @azure_client2.get_virtual_machine_by_name(instance_id)
            location = vm[:location]
            instance_type = vm[:vm_size]
            default_storage_account_type = get_storage_account_type_by_instance_type(instance_type)
          end
          storage_account_type = cloud_properties.fetch('storage_account_type', default_storage_account_type)
          caching = cloud_properties.fetch('caching', 'None')
          validate_disk_caching(caching)
          disk_id = @disk_manager2.create_disk(location, size/1024, storage_account_type, caching)
        else
          storage_account_name = azure_properties['storage_account_name']
          caching = cloud_properties.fetch('caching', 'None')
          validate_disk_caching(caching)
          unless instance_id.nil?
            @logger.info("Create disk for vm #{instance_id}")
            storage_account_name = get_storage_account_name_from_instance_id(instance_id)
          end

          disk_id = @disk_manager.create_disk(size/1024, storage_account_name, caching)
        end
        disk_id
      end
    end

    ##
    # Deletes a disk
    # Will raise an exception if the disk is attached to a VM
    #
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def delete_disk(disk_id)
      with_thread_name("delete_disk(#{disk_id})") do
        if @use_managed_disks
          # A managed disk may be created from an old blob disk, so its name still starts with 'bosh-data' instead of 'bosh-disk-data'
          # CPI checks whether the managed disk with the name exists. If not, delete the old blob disk.
          unless disk_id.start_with?(MANAGED_DATA_DISK_PREFIX)
            disk = @disk_manager2.get_disk(disk_id)
            return @disk_manager.delete_disk(disk_id) if disk.nil?
          end
          @disk_manager2.delete_disk(disk_id)
        else
          @disk_manager.delete_disk(disk_id)
        end
      end
    end

    # Attaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def attach_disk(instance_id, disk_id)
      with_thread_name("attach_disk(#{instance_id},#{disk_id})") do
        if @use_managed_disks
          disk = @disk_manager2.get_disk(disk_id)
          unless is_managed_vm?(instance_id)
            cloud_error("Cannot attach a managed disk to a VM with unmanaged disks") unless disk.nil?
            @logger.debug("attach_disk - although use_managed_disks is enabled, will still attach the unmanaged disk `#{disk_id}' to the VM `#{instance_id}' with unmanaged disks")
          else
            if disk.nil?
              begin
                blob_uri = @disk_manager.get_disk_uri(disk_id)
                storage_account_name = get_storage_account_name_from_disk_id(disk_id)
                storage_account = @azure_client2.get_storage_account_by_name(storage_account_name)
                location = storage_account[:location]
                # Can not use the type of the default storage account because only Standard_LRS and Premium_LRS are supported for managed disk.
                account_type = (storage_account[:account_type] == STORAGE_ACCOUNT_TYPE_PREMIUM_LRS) ? STORAGE_ACCOUNT_TYPE_PREMIUM_LRS : STORAGE_ACCOUNT_TYPE_STANDARD_LRS
                @logger.debug("attach_disk - Migrating the unmanaged disk `#{disk_id}' to a managed disk")
                @disk_manager2.create_disk_from_blob(disk_id, blob_uri, location, account_type)

                # Set below metadata but not delete it.
                # Users can manually delete all blobs in container `bosh` whose names start with `bosh-data` after migration is finished.
                @blob_manager.set_blob_metadata(storage_account_name, DISK_CONTAINER, "#{disk_id}.vhd", METADATA_FOR_MIGRATED_BLOB_DISK)
              rescue => e
                if account_type # There are no other functions between defining account_type and @disk_manager2.create_disk_from_blob
                  begin
                    @disk_manager2.delete_disk(disk_id)
                  rescue => err
                    @logger.error("attach_disk - Failed to delete the created managed disk #{disk_id}. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                  end
                end
                cloud_error("attach_disk - Failed to create the managed disk for #{disk_id}. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
              end
            end
          end
        end

        lun = @vm_manager.attach_disk(instance_id, disk_id)

        update_agent_settings(instance_id) do |settings|
          settings["disks"] ||= {}
          settings["disks"]["persistent"] ||= {}
          settings["disks"]["persistent"][disk_id] =  {
            'lun'            => lun,
            'host_device_id' => get_scsi_host_device_id(azure_properties['environment']),

            # For compatiblity with old stemcells
            'path'           => get_disk_path_name(lun.to_i)
          }
        end

        @logger.info("Attached the disk `#{disk_id}' to the instance `#{instance_id}', lun `#{lun}'")
      end
    end

    # Detaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def detach_disk(instance_id, disk_id)
      with_thread_name("detach_disk(#{instance_id},#{disk_id})") do

        update_agent_settings(instance_id) do |settings|
          settings["disks"] ||= {}
          settings["disks"]["persistent"] ||= {}
          settings["disks"]["persistent"].delete(disk_id)
        end

        @vm_manager.detach_disk(instance_id, disk_id)

        @logger.info("Detached `#{disk_id}' from `#{instance_id}'")
      end
    end

    # List the attached disks of the VM.
    # @param [String] instance_id is the CPI-standard instance_id (eg, returned from current_vm_id)
    # @return [array[String]] list of opaque disk_ids that can be used with the
    # other disk-related methods on the CPI
    def get_disks(instance_id)
      with_thread_name("get_disks(#{instance_id})") do
        disks = []
        vm = @vm_manager.find(instance_id)
        raise Bosh::Clouds::VMNotFound, "VM `#{instance_id}' cannot be found" if vm.nil?
        vm[:data_disks].each do |disk|
          disks << disk[:name] unless is_ephemeral_disk?(disk[:name])
        end
        disks
      end
    end

    # Take snapshot of disk
    # @param [String] disk_id disk id of the disk to take the snapshot of
    # @param [Hash] metadata metadata key/value pairs
    # @return [String] snapshot id
    def snapshot_disk(disk_id, metadata = {})
      with_thread_name("snapshot_disk(#{disk_id},#{metadata})") do
        if disk_id.start_with?(MANAGED_DATA_DISK_PREFIX)
          snapshot_id = @disk_manager2.snapshot_disk(disk_id, encode_metadata(metadata))
        else
          disk = @disk_manager2.get_disk(disk_id)
          unless disk.nil?
            snapshot_id = @disk_manager2.snapshot_disk(disk_id, encode_metadata(metadata))
          else
            snapshot_id = @disk_manager.snapshot_disk(disk_id, encode_metadata(metadata))
          end
        end

        @logger.info("Take a snapshot `#{snapshot_id}' for the disk `#{disk_id}'")
        snapshot_id
      end
    end

    # Delete a disk snapshot
    # @param [String] snapshot_id snapshot id to delete
    # @return [void]
    def delete_snapshot(snapshot_id)
      with_thread_name("delete_snapshot(#{snapshot_id})") do
        if snapshot_id.start_with?(MANAGED_DATA_DISK_PREFIX)
          @disk_manager2.delete_snapshot(snapshot_id)
        else
          @disk_manager.delete_snapshot(snapshot_id)
        end
        @logger.info("The snapshot `#{snapshot_id}' is deleted")
      end
    end

    ##
    # Set metadata for a disk
    #
    # Optional. Implement to provide more information for the IaaS.
    #
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @param [Hash] metadata metadata key/value pairs
    # @return [void]
    def set_disk_metadata(disk_id, metadata)
      @logger.info("set_disk_metadata(#{disk_id}, #{metadata})")
      # TBD
      raise Bosh::Clouds::NotImplemented
    end

    private

    def agent_properties
      @agent_properties ||= options.fetch('agent', {})
    end

    def azure_properties
      @azure_properties ||= options.fetch('azure')
    end

    def init_registry
      registry_properties = options.fetch('registry')
      registry_endpoint   = registry_properties.fetch('endpoint')
      registry_user       = registry_properties.fetch('user')
      registry_password   = registry_properties.fetch('password')

      # Registry updates are not really atomic in relation to
      # Azure API calls, so they might get out of sync.
      @registry = Bosh::Cpi::RegistryClient.new(registry_endpoint, registry_user, registry_password)
    end

    def init_azure
      @azure_client2           = Bosh::AzureCloud::AzureClient2.new(azure_properties, @logger)
      @blob_manager            = Bosh::AzureCloud::BlobManager.new(azure_properties, @azure_client2)
      @disk_manager            = Bosh::AzureCloud::DiskManager.new(azure_properties, @blob_manager)
      @storage_account_manager = Bosh::AzureCloud::StorageAccountManager.new(azure_properties, @blob_manager, @disk_manager, @azure_client2)
      @table_manager           = Bosh::AzureCloud::TableManager.new(azure_properties, @storage_account_manager, @azure_client2)
      @stemcell_manager        = Bosh::AzureCloud::StemcellManager.new(@blob_manager, @table_manager, @storage_account_manager)
      @disk_manager2           = Bosh::AzureCloud::DiskManager2.new(@azure_client2)
      @stemcell_manager2       = Bosh::AzureCloud::StemcellManager2.new(@blob_manager, @table_manager, @storage_account_manager, @azure_client2)
      @light_stemcell_manager  = Bosh::AzureCloud::LightStemcellManager.new(@blob_manager, @storage_account_manager, @azure_client2)
      @vm_manager              = Bosh::AzureCloud::VMManager.new(azure_properties, @registry.endpoint, @disk_manager, @disk_manager2, @azure_client2)
    rescue Net::OpenTimeout => e
      cloud_error("Please make sure the CPI has proper network access to Azure. #{e.inspect}") # TODO: Will it throw the error when initializing the client and manager
    end

    # Generates initial agent settings. These settings will be read by agent
    # from AZURE registry (also a BOSH component) on a target instance. Disk
    # conventions for Azure are:
    # system disk: /dev/sda
    # ephemeral disk: data disk at lun 0 or nil if use OS disk to store the ephemeral data
    #
    # @param [String] agent_id Agent id (will be picked up by agent to
    #   assume its identity
    # @param [Hash] network_spec Agent network spec
    # @param [Hash] environment
    # @param [Hash] vm_params
    # @return [Hash]
    def initial_agent_settings(agent_id, network_spec, environment, vm_params)
      settings = {
        "vm" => {
          "name" => vm_params[:name]
        },
        "agent_id" => agent_id,
        "networks" => agent_network_spec(network_spec),
        "disks" => {
          "system" => '/dev/sda',
          "persistent" => {}
        }
      }

      unless vm_params[:ephemeral_disk].nil?
        # Azure uses a data disk as the ephermeral disk and the lun is 0
        settings["disks"]["ephemeral"] = {
          'lun'            => '0',
          'host_device_id' => get_scsi_host_device_id(azure_properties['environment']),

          # For compatiblity with old stemcells
          'path'           => get_disk_path_name(0)
        }
      end

      settings["env"] = environment if environment
      settings.merge(agent_properties)
    end

    def update_agent_settings(instance_id)
      unless block_given?
        raise ArgumentError, "block is not provided"
      end

      settings = registry.read_settings(instance_id)
      yield settings
      registry.update_settings(instance_id, settings)
    end

    def agent_network_spec(network_spec)
      Hash[*network_spec.map do |name, settings|
        settings["use_dhcp"] = true
        [name, settings]
      end.flatten]
    end

    def get_disk_path_name(lun)
      if((lun + 2) < 26)
        "/dev/sd#{('c'.ord + lun).chr}"
      else
        "/dev/sd#{('a'.ord + (lun + 2 - 26) / 26).chr}#{('a'.ord + (lun + 2) % 26).chr}"
      end
    end

    def get_scsi_host_device_id(environment)
      if environment == 'AzureStack'
        AZURESTACK_SCSI_HOST_DEVICE_ID
      else
        AZURE_SCSI_HOST_DEVICE_ID
      end
    end
  end
end
