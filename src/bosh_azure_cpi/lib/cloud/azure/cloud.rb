# frozen_string_literal: true

module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_reader   :registry
    attr_reader   :config
    # Below defines are for test purpose
    attr_reader   :azure_client, :blob_manager, :meta_store, :storage_account_manager, :vm_manager, :instance_type_mapper
    attr_reader   :disk_manager, :disk_manager2, :stemcell_manager, :stemcell_manager2, :light_stemcell_manager
    attr_reader   :props_factory
    attr_reader   :api_version, :stemcell_api_version
    include Helpers

    # CPI API Version
    CURRENT_API_VERSION = 2

    # First stemcell API version and CPI API version that supports registry-less operation
    STEMCELL_API_VERSION_REGISTRYLESS = 2
    API_VERSION_REGISTRYLESS = 2

    ##
    # Cloud initialization
    #
    # @param [Hash] options cloud options
    def initialize(options, api_version)
      options_dup = options.dup.freeze

      @api_version = api_version || 1

      @logger = Bosh::Clouds::Config.logger

      @config = Bosh::AzureCloud::ConfigFactory.build(options_dup)

      @stemcell_api_version = @config.azure.stemcell_api_version

      request_id = options_dup['azure']['request_id']
      Bosh::AzureCloud::CPILogger.set_request_id(request_id) if request_id

      @use_managed_disks = _azure_config.use_managed_disks

      _init_cpi_lock_dir

      @props_factory = Bosh::AzureCloud::PropsFactory.new(@config)

      @telemetry_manager = Bosh::AzureCloud::TelemetryManager.new(_azure_config)
      @telemetry_manager.monitor('initialize') do
        _init_registry
      end
    end

    ##
    # Returns information about the CPI to help the Director to make decisions
    # on which CPI to call for certain operations in a multi CPI scenario.
    #
    # @return [Hash] Only one key 'stemcell_formats' is supported, which are stemcell formats supported by the CPI.
    #                Currently used in combination with create_stemcell by the Director to determine which CPI to call when uploading a stemcell.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/info/
    #
    def info
      @telemetry_manager.monitor('info') do
        {
          'stemcell_formats' => %w[azure-vhd azure-light],
          'api_version' => CURRENT_API_VERSION
        }
      end
    end

    ##
    # Creates a reusable VM image in the IaaS from the stemcell image. It's used later for creating VMs.
    #
    # @param [String] image_path       Path to the stemcell image extracted from the stemcell tarball on a local filesystem.
    # @param [Hash]   cloud_properties Cloud properties hash extracted from the stemcell tarball.
    #
    # @return [String] stemcell_cid Cloud ID of the created stemcell. It's used later by create_vm and delete_stemcell.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/create-stemcell/
    #
    def create_stemcell(image_path, cloud_properties)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("create_stemcell(#{image_path}, #{cloud_properties})") do
        extras = {
          'stemcell' => "#{cloud_properties.fetch('name', 'unknown_name')}-#{cloud_properties.fetch('version', 'unknown_version')}"
        }
        @telemetry_manager.monitor('create_stemcell', extras: extras) do
          if has_light_stemcell_property?(cloud_properties)
            @light_stemcell_manager.create_stemcell(cloud_properties)
          elsif @use_managed_disks
            @stemcell_manager2.create_stemcell(image_path, cloud_properties)
          else
            @stemcell_manager.create_stemcell(image_path, cloud_properties)
          end
        end
      end
    end

    ##
    # Deletes previously created stemcell. Assume that none of the VMs require presence of the stemcell.
    #
    # @param [String] stemcell_cid Cloud ID of the stemcell to delete; returned from create_stemcell.
    #
    # @return [void]
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/delete-stemcell/
    #
    def delete_stemcell(stemcell_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("delete_stemcell(#{stemcell_cid})") do
        @telemetry_manager.monitor('delete_stemcell', id: stemcell_cid) do
          if is_light_stemcell_cid?(stemcell_cid)
            @light_stemcell_manager.delete_stemcell(stemcell_cid)
          elsif @use_managed_disks
            @stemcell_manager2.delete_stemcell(stemcell_cid)
          else
            @stemcell_manager.delete_stemcell(stemcell_cid)
          end
        end
      end
    end

    ##
    # Creates a new VM based on the stemcell.
    # Created VM must be powered on and accessible on the provided networks.
    # Waiting for the VM to finish booting is not required because the Director waits until the Agent on the VM responds back.
    # Make sure to properly delete created resources if VM cannot be successfully created.
    #
    # @param [String]           agent_id         ID selected by the Director for the VM's agent
    # @param [String]           stemcell_cid     Cloud ID of the stemcell to use as a base image for new VM,
    #                                            which was once returned by {#create_stemcell}
    # @param [Hash]             cloud_properties Cloud properties hash specified in the deployment manifest under VM's resource pool.
    #                                            https://bosh.io/docs/azure-cpi/#resource-pools
    # @param [Hash]             networks         Networks hash that specifies which VM networks must be configured.
    # @param [Array of strings] disk_cids        Array of disk cloud IDs for each disk that created VM will most likely be attached;
    #                                            they could be used to optimize VM placement so that disks are located nearby.
    # @param [Hash]             environment      Resource pool's env hash specified in deployment manifest including initial properties added by the BOSH director.
    #
    # @return [String] vm_cid Cloud ID of the created VM. Later used by {#attach_disk}, {#detach_disk} and {#delete_vm}.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/create-vm/
    #
    def create_vm(agent_id, stemcell_cid, cloud_properties, networks, disk_cids = nil, environment = {})
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      # environment may contain credentials so we must not log it
      @logger.info("create_vm(#{agent_id}, #{stemcell_cid}, #{cloud_properties}, #{networks}, #{disk_cids}, ...)")
      with_thread_name("create_vm(#{agent_id}, ...)") do
        bosh_vm_meta = Bosh::AzureCloud::BoshVMMeta.new(agent_id, stemcell_cid)
        vm_props = @props_factory.parse_vm_props(cloud_properties)
        if vm_props.instance_type.nil?
          extras = { 'instance_types' => vm_props.instance_types } unless vm_props.instance_types.nil?
        else
          extras = { 'instance_type' => vm_props.instance_type }
        end
        @telemetry_manager.monitor('create_vm', id: bosh_vm_meta.agent_id, extras: extras) do
          # These resources should be in the same location for a VM: VM, NIC, disk(storage account or managed disk).
          # And NIC must be in the same location with VNET, so CPI will use VNET's location as default location for the resources related to the VM.
          network_configurator = NetworkConfigurator.new(_azure_config, networks)
          network = network_configurator.networks[0]
          vnet = @azure_client.get_virtual_network_by_name(network.resource_group_name, network.virtual_network_name)
          cloud_error("Cannot find the virtual network '#{network.virtual_network_name}' under resource group '#{network.resource_group_name}'") if vnet.nil?
          location = vnet[:location]
          location_in_global_configuration = _azure_config.location
          cloud_error("The location in the global configuration '#{location_in_global_configuration}' is different from the location of the virtual network '#{location}'") if !location_in_global_configuration.nil? && location_in_global_configuration != location

          agent_settings = Bosh::AzureCloud::BoshAgentUtil.new(_should_write_to_registry?)

          instance_id, vm_params = @vm_manager.create(
            bosh_vm_meta,
            location,
            vm_props,
            disk_cids,
            network_configurator,
            environment,
            agent_settings,
            networks,
            @config,
          )

          @logger.info("Created new vm '#{instance_id}'")

          begin
            settings = agent_settings.initial_agent_settings(
                bosh_vm_meta.agent_id,
                networks,
                environment,
                vm_params,
                @config
            )
            registry.update_settings(instance_id.to_s, settings) if _should_write_to_registry?

            _create_vm_response(instance_id.to_s, networks)
          rescue StandardError => e
            @logger.error(%(Failed to update registry after new vm was created: #{e.inspect}\n#{e.backtrace.join("\n")}))
            @vm_manager.delete(instance_id)
            raise e
          end
        end
      end
    end

    ##
    # Deletes the VM.
    # This method will be called while the VM still has persistent disks attached.
    # It's important to make sure that IaaS behaves appropriately in this case and properly disassociates persistent disks from the VM.
    # To avoid losing track of VMs, make sure to raise an error if VM deletion is not absolutely certain.
    #
    # @param [String] vm_cid Cloud ID of the VM to delete; returned from create_vm.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-vm/
    #
    def delete_vm(vm_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("delete_vm(#{vm_cid})") do
        @telemetry_manager.monitor('delete_vm', id: vm_cid) do
          @logger.info("Deleting instance '#{vm_cid}'")
          @vm_manager.delete(InstanceId.parse(vm_cid, _azure_config.resource_group_name))
        end
      end
    end

    ##
    # Checks for VM presence in the IaaS.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the VM still exists.
    #
    # @param [String] vm_cid Cloud ID of the VM to check; returned from create_vm.
    #
    # @return [Boolean] exists True if VM is present.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/has-vm/
    #
    def has_vm?(vm_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("has_vm?(#{vm_cid})") do
        @telemetry_manager.monitor('has_vm?', id: vm_cid) do
          vm = @vm_manager.find(InstanceId.parse(vm_cid, _azure_config.resource_group_name))
          !vm.nil? && vm[:provisioning_state] != 'Deleting'
        end
      end
    end

    ##
    # Reboots the VM. Assume that VM can be either be powered on or off at the time of the call.
    # Waiting for the VM to finish rebooting is not required because the Director waits until the Agent on the VM responds back.
    #
    # @param [String] vm_cid Cloud ID of the VM to reboot; returned from create_vm.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/reboot-vm/
    #
    def reboot_vm(vm_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("reboot_vm(#{vm_cid})") do
        @telemetry_manager.monitor('reboot_vm', id: vm_cid) do
          @vm_manager.reboot(InstanceId.parse(vm_cid, _azure_config.resource_group_name))
        end
      end
    end

    ##
    # Sets VM's metadata to make it easier for operators to categorize VMs when looking at the IaaS management console.
    #
    # @param [String] vm_cid   Cloud ID of the VM to modify; returned from create_vm.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/set-vm-metadata/
    #
    def set_vm_metadata(vm_cid, metadata)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("set_vm_metadata(#{vm_cid})") do
        @telemetry_manager.monitor('set_vm_metadata', id: vm_cid) do
          @logger.info("set_vm_metadata(#{vm_cid}, #{metadata})")
          @vm_manager.set_metadata(InstanceId.parse(vm_cid, _azure_config.resource_group_name), encode_metadata(metadata))
        end
      end
    end

    ##
    # Returns a hash that can be used as VM cloud_properties when calling create_vm; it describes the IaaS instance type closest to the arguments passed.
    #
    # @param  [Hash] desired_instance_size Parameters of the desired size of the VM consisting of the following keys:
    #                                      cpu [Integer]: Number of virtual cores desired
    #                                      ram [Integer]: Amount of RAM, in MiB (i.e. 4096 for 4 GiB)
    #                                      ephemeral_disk_size [Integer]: Size of ephemeral disk, in MB
    #
    # @return [Hash] cloud_properties an IaaS-specific set of cloud properties that define the size of the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/calculate-vm-cloud-properties/
    #
    def calculate_vm_cloud_properties(desired_instance_size)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("calculate_vm_cloud_properties(#{desired_instance_size})") do
        @telemetry_manager.monitor('calculate_vm_cloud_properties') do
          @logger.info("calculate_vm_cloud_properties(#{desired_instance_size})")
          location = _azure_config.location
          cloud_error("Missing the property 'location' in the global configuration") if location.nil?

          required_keys = %w[cpu ram ephemeral_disk_size]
          missing_keys = required_keys.reject { |key| desired_instance_size[key] }
          unless missing_keys.empty?
            missing_keys.map! { |k| "'#{k}'" }
            raise "Missing VM cloud properties: #{missing_keys.join(', ')}"
          end

          available_vm_sizes = @azure_client.list_available_virtual_machine_sizes_by_location(location)
          instance_types = @instance_type_mapper.map(desired_instance_size, available_vm_sizes)
          {
            'instance_types' => instance_types,
            'ephemeral_disk' => {
              'size' => (desired_instance_size['ephemeral_disk_size'] / 1024.0).ceil * 1024
            }
          }
        end
      end
    end

    ##
    # Creates disk with specific size. Disk does not belong to any given VM.
    #
    # @param [Integer]          size             Size of the disk in MiB.
    # @param [Hash]             cloud_properties Cloud properties hash specified in the deployment manifest under the disk pool.
    #                                            https://bosh.io/docs/azure-cpi/#disk-pools
    # @param [optional, String] vm_cid           Cloud ID of the VM created disk will most likely be attached;
    #                                            it could be used to .optimize disk placement so that disk is located near the VM.
    #
    # @return [String] disk_cid Cloud ID of the created disk. It's used later by attach_disk, detach_disk, and delete_disk.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/create-disk/
    #
    def create_disk(size, cloud_properties, vm_cid = nil)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("create_disk(#{size}, #{cloud_properties})") do
        id = vm_cid.nil? ? '' : vm_cid
        extras = { 'disk_size' => size }
        @telemetry_manager.monitor('create_disk', id: id, extras: extras) do
          validate_disk_size(size)
          disk_id = nil
          if @use_managed_disks
            if vm_cid.nil?
              # If instance_id is nil, the managed disk will be created in the resource group location.
              resource_group_name = _azure_config.resource_group_name
              resource_group = @azure_client.get_resource_group(resource_group_name)
              location = resource_group[:location]
              default_storage_account_type = STORAGE_ACCOUNT_TYPE_STANDARD_LRS
              zone = nil
            else
              instance_id = InstanceId.parse(vm_cid, _azure_config.resource_group_name)
              cloud_error('Cannot create a managed disk for a VM with unmanaged disks') unless instance_id.use_managed_disks?
              resource_group_name = instance_id.resource_group_name
              # If the instance is a managed VM, the managed disk will be created in the location of the VM.
              vm = @azure_client.get_virtual_machine_by_name(resource_group_name, instance_id.vm_name)
              location = vm[:location]
              instance_type = vm[:vm_size]
              zone = vm[:zone]
              default_storage_account_type = get_storage_account_type_by_instance_type(instance_type)
            end
            storage_account_type = cloud_properties.fetch('storage_account_type', default_storage_account_type)
            caching = cloud_properties.fetch('caching', 'None')
            validate_disk_caching(caching)
            disk_id = DiskId.create(caching, true, resource_group_name: resource_group_name)
            @disk_manager2.create_disk(disk_id, location, size / 1024, storage_account_type, zone)
          else
            storage_account_name = _azure_config.storage_account_name
            caching = cloud_properties.fetch('caching', 'None')
            validate_disk_caching(caching)
            unless vm_cid.nil?
              instance_id = InstanceId.parse(vm_cid, _azure_config.resource_group_name)
              @logger.info("Create disk for vm '#{instance_id.vm_name}'")
              storage_account_name = instance_id.storage_account_name
            end
            disk_id = DiskId.create(caching, false, storage_account_name: storage_account_name)
            @disk_manager.create_disk(disk_id, size / 1024)
          end
          disk_id.to_s
        end
      end
    end

    ##
    # Deletes disk. Assume that disk was detached from all VMs.
    # To avoid losing track of disks, make sure to raise an error if disk deletion is not absolutely certain.
    #
    # @param [String] disk_cid Cloud ID of the disk to delete; returned from create_disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-disk/
    #
    def delete_disk(disk_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("delete_disk(#{disk_cid})") do
        @telemetry_manager.monitor('delete_disk', id: disk_cid) do
          disk_id = DiskId.parse(disk_cid, _azure_config.resource_group_name)
          if @use_managed_disks
            # A managed disk may be created from an old blob disk, so its name still starts with 'bosh-data' instead of 'bosh-disk-data'
            # CPI checks whether the managed disk with the name exists. If not, delete the old blob disk.
            unless disk_id.disk_name.start_with?(MANAGED_DATA_DISK_PREFIX)
              disk = @disk_manager2.get_data_disk(disk_id)
              return @disk_manager.delete_data_disk(disk_id) if disk.nil?
            end
            @disk_manager2.delete_data_disk(disk_id)
          else
            @disk_manager.delete_data_disk(disk_id)
          end
        end
      end
    end

    ##
    # Resizes disk with IaaS-native methods. Assume that disk was detached from all VMs.
    # Set property director.enable_cpi_resize_disk to true to have the Director call this method.
    # Depending on the capabilities of the underlying infrastructure, this method may raise an
    # Bosh::Clouds::NotSupported error when the new_size is smaller than the current disk size.
    # The same error is raised when the method is not implemented.
    # If Bosh::Clouds::NotSupported is raised, the Director falls back to creating a new disk and copying data.
    #
    # @param [String]  disk_cid Cloud ID of the disk to check; returned from create_disk.
    # @param [Integer] new_size New disk size in MiB.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/resize-disk/
    #
    def resize_disk(disk_cid, new_size)
      @logger.info("resize_disk(#{disk_cid}, #{new_size})")
      raise Bosh::Clouds::NotSupported
    end

    ##
    # Checks for disk presence in the IaaS.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the disk still exists.
    #
    # @param [String] disk_cid Cloud ID of the disk to check; returned from create_disk.
    #
    # @return [Boolean] True if disk is present.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/has-disk/
    #
    def has_disk?(disk_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("has_disk?(#{disk_cid})") do
        @telemetry_manager.monitor('has_disk?', id: disk_cid) do
          disk_id = DiskId.parse(disk_cid, _azure_config.resource_group_name)
          if disk_id.disk_name.start_with?(MANAGED_DATA_DISK_PREFIX)
            return @disk_manager2.has_data_disk?(disk_id)
          else
            ##
            # when disk name starts with DATA_DISK_PREFIX, the disk could be an unmanaged disk OR a managed disk (migrated from unmanaged disk)
            #
            # if @use_managed_disks is true, and
            #   if the managed disk is found (the unmanaged disk is already migrated to managed disk for sure), return true;
            #   if the managed disk is not found, but the unmanaged disk is already migrated to managed disk, return false;
            #   if the managed disk is not found, and the unmanaged disk not yet migrated (bosh is updated but vm is not), check existence of the unmanaged disk.
            # if @use_managed_disks is false, check existence of the unmanaged disk.
            if @use_managed_disks
              return true if @disk_manager2.has_data_disk?(disk_id)
              return false if @disk_manager.is_migrated?(disk_id) # the managed disk is not found, and the unmanaged disk is already migrated to managed disk
            end
            return @disk_manager.has_data_disk?(disk_id)
          end
        end
      end
    end

    ##
    # Attaches disk to the VM.
    # Typically each VM will have one disk attached at a time to store persistent data;
    # however, there are important cases when multiple disks may be attached to a VM.
    # Most common scenario involves persistent data migration from a smaller to a larger disk.
    # Given a VM with a smaller disk attached, the operator decides to increase the disk size for that VM,
    # so new larger disk is created, it is then attached to the VM.
    # The Agent then copies over the data from one disk to another, and smaller disk subsequently is detached and deleted.
    # Agent settings should have been updated with necessary information about given disk.
    #
    # @param [String] vm_cid   Cloud ID of the VM.
    # @param [String] disk_cid Cloud ID of the disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/attach-disk/
    #
    def attach_disk(vm_cid, disk_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("attach_disk(#{vm_cid},#{disk_cid})") do
        @telemetry_manager.monitor('attach_disk', id: vm_cid) do
          instance_id = InstanceId.parse(vm_cid, _azure_config.resource_group_name)
          disk_id = DiskId.parse(disk_cid, _azure_config.resource_group_name)
          vm_name = instance_id.vm_name
          disk_name = disk_id.disk_name

          vm = @vm_manager.find(instance_id)

          # Workaround for issue #280
          # Issue root cause: Attaching a data disk to a VM whose OS disk is busy might lead to OS hang.
          #                   If 'use_root_disk' is true in vm_types/vm_extensions, release packages will be copied to OS disk before attaching data disk,
          #                   it will continuously write the data to OS disk, that is why OS disk is busy.
          # Workaround: Sleep 30 seconds before attaching data disk, to wait for completion of data writing.
          has_ephemeral_disk = false
          vm[:data_disks].each do |disk|
            has_ephemeral_disk = true if is_ephemeral_disk?(disk[:name])
          end
          unless has_ephemeral_disk
            @logger.debug('Sleep 30 seconds before attaching data disk - workaround for issue #280')
            sleep(30)
          end

          if @use_managed_disks
            disk = @disk_manager2.get_data_disk(disk_id)
            vm_zone = vm[:zone]
            if instance_id.use_managed_disks?
              if disk.nil?
                if disk_id.disk_name.start_with?(DATA_DISK_PREFIX)
                  @logger.info("attach_disk - migrate the disk '#{disk_name}' from unmanaged to managed")
                  begin
                    storage_account_name = disk_id.storage_account_name
                    blob_uri = @disk_manager.get_data_disk_uri(disk_id)
                    storage_account = @azure_client.get_storage_account_by_name(storage_account_name)
                    location = storage_account[:location]
                    # Can not use the type of the default storage account because only Standard_LRS and Premium_LRS are supported for managed disk.
                    account_type = storage_account[:sku_tier] == SKU_TIER_PREMIUM ? STORAGE_ACCOUNT_TYPE_PREMIUM_LRS : STORAGE_ACCOUNT_TYPE_STANDARD_LRS
                    @logger.debug("attach_disk - Migrating the unmanaged disk '#{disk_name}' to a managed disk")
                    @disk_manager2.create_disk_from_blob(disk_id, blob_uri, location, account_type, vm_zone)

                    # Set below metadata but not delete it.
                    # Users can manually delete all blobs in container 'bosh' whose names start with 'bosh-data' after migration is finished.
                    @blob_manager.set_blob_metadata(storage_account_name, DISK_CONTAINER, "#{disk_name}.vhd", METADATA_FOR_MIGRATED_BLOB_DISK)
                  rescue StandardError => e
                    if account_type # There are no other functions between defining account_type and @disk_manager2.create_disk_from_blob
                      begin
                        @disk_manager2.delete_data_disk(disk_id)
                      rescue StandardError => err
                        @logger.error("attach_disk - Failed to delete the created managed disk #{disk_name}. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                      end
                    end
                    cloud_error("attach_disk - Failed to create the managed disk for #{disk_name}. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                  end
                end
              elsif disk[:zone].nil? && !vm_zone.nil?
                @logger.info("attach_disk - migrate the managed disk '#{disk_name}' from regional to zonal")
                begin
                  @disk_manager2.migrate_to_zone(disk_id, disk, vm_zone)
                rescue StandardError => e
                  cloud_error("attach_disk - Failed to migrate disk #{disk_name} to zone #{vm_zone}. Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                end
              end
            else
              cloud_error('Cannot attach a managed disk to a VM with unmanaged disks') unless disk.nil?
              @logger.debug("attach_disk - although use_managed_disks is enabled, will still attach the unmanaged disk '#{disk_name}' to the VM '#{vm_name}' with unmanaged disks")
            end
          end

          lun = @vm_manager.attach_disk(instance_id, disk_id)

          disk_hints = {
            'lun' => lun,
            'host_device_id' => AZURE_SCSI_HOST_DEVICE_ID
          }

          if _should_write_to_registry?
            _update_agent_settings(instance_id.to_s) do |settings|
              settings['disks'] ||= {}
              settings['disks']['persistent'] ||= {}
              settings['disks']['persistent'][disk_id.to_s] = disk_hints
            end
          end

          @logger.info("Attached the disk '#{disk_id}' to the instance '#{instance_id}', lun '#{lun}'")

          _attach_disk_response(disk_hints)
        end
      end
    end

    ##
    # Detaches disk from the VM.
    # If the persistent disk is attached to a VM that will be deleted, it's more likely delete_vm CPI
    # method will be called without a call to detach_disk with an expectation that delete_vm will
    # make sure disks are disassociated from the VM upon its deletion.
    # Agent settings should have been updated to remove information about given disk.
    #
    # @param [String] vm_cid   Cloud ID of the VM.
    # @param [String] disk_cid Cloud ID of the disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/detach-disk/
    #
    def detach_disk(vm_cid, disk_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("detach_disk(#{vm_cid},#{disk_cid})") do
        @telemetry_manager.monitor('detach_disk', id: vm_cid) do

          if _should_write_to_registry?
            _update_agent_settings(vm_cid) do |settings|
              settings['disks'] ||= {}
              settings['disks']['persistent'] ||= {}
              settings['disks']['persistent'].delete(disk_cid)
            end
          end

          @vm_manager.detach_disk(
            InstanceId.parse(vm_cid, _azure_config.resource_group_name),
            DiskId.parse(disk_cid, _azure_config.resource_group_name)
          )

          @logger.info("Detached '#{disk_cid}' from '#{vm_cid}'")
        end
      end
    end

    ##
    # Sets disk's metadata to make it easier for operators to categorize disks when looking at the IaaS management console.
    # Disk metadata is written when the disk is attached to a VM. Metadata is not removed when disk is detached or VM is deleted.
    #
    # @param [String] disk_cid Cloud ID of the disk to modify; returned from create_disk.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/set-disk-metadata/
    #
    def set_disk_metadata(disk_cid, metadata)
      @logger.info("set_disk_metadata(#{disk_cid}, #{metadata})")
      raise Bosh::Clouds::NotImplemented
    end

    ##
    # Returns list of disks currently attached to the VM.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the VM has required disks attached.
    #
    # @param [String] vm_cid Cloud ID of the VM.
    #
    # @return [Array of strings] disk_cids Array of disk_cid that are currently attached to the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/get-disks/
    #
    def get_disks(vm_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("get_disks(#{vm_cid})") do
        @telemetry_manager.monitor('get_disks', id: vm_cid) do
          disks = []
          vm = @vm_manager.find(InstanceId.parse(vm_cid, _azure_config.resource_group_name))
          raise Bosh::Clouds::VMNotFound, "VM '#{vm_cid}' cannot be found" if vm.nil?

          vm[:data_disks].each do |disk|
            disks << disk[:disk_bosh_id] unless is_ephemeral_disk?(disk[:name]) # disk_bosh_id is same to disk_cid
          end
          disks
        end
      end
    end

    ##
    # Takes a snapshot of the disk.
    #
    # @param [String] disk_cid Cloud ID of the disk.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [String] snapshot_cid Cloud ID of the disk snapshot.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/snapshot-disk/
    #
    def snapshot_disk(disk_cid, metadata = {})
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("snapshot_disk(#{disk_cid},#{metadata})") do
        @telemetry_manager.monitor('snapshot_disk', id: disk_cid) do
          disk_id = DiskId.parse(disk_cid, _azure_config.resource_group_name)
          resource_group_name = disk_id.resource_group_name
          disk_name = disk_id.disk_name
          caching = disk_id.caching
          if disk_name.start_with?(MANAGED_DATA_DISK_PREFIX)
            snapshot_id = DiskId.create(caching, true, resource_group_name: resource_group_name)
            @disk_manager2.snapshot_disk(snapshot_id, disk_name, encode_metadata(metadata))
          else
            disk = @disk_manager2.get_data_disk(disk_id)
            if disk.nil?
              storage_account_name = disk_id.storage_account_name
              snapshot_name = @disk_manager.snapshot_disk(storage_account_name, disk_name, encode_metadata(metadata))
              snapshot_id = DiskId.create(caching, false, disk_name: snapshot_name, storage_account_name: storage_account_name)
            else
              snapshot_id = DiskId.create(caching, true, resource_group_name: resource_group_name)
              @disk_manager2.snapshot_disk(snapshot_id, disk_name, encode_metadata(metadata))
            end
          end

          @logger.info("Take a snapshot '#{snapshot_id}' for the disk '#{disk_id}'")
          snapshot_id.to_s
        end
      end
    end

    ##
    # Deletes the disk snapshot.
    #
    # @param [String] snapshot_cid Cloud ID of the disk snapshot.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-snapshot/
    #
    def delete_snapshot(snapshot_cid)
      @telemetry_manager.monitor('initialize') do
        _init_azure
      end
      with_thread_name("delete_snapshot(#{snapshot_cid})") do
        @telemetry_manager.monitor('delete_snapshot', id: snapshot_cid) do
          snapshot_id = DiskId.parse(snapshot_cid, _azure_config.resource_group_name)
          snapshot_name = snapshot_id.disk_name
          if snapshot_name.start_with?(MANAGED_DATA_DISK_PREFIX)
            @disk_manager2.delete_snapshot(snapshot_id)
          else
            @disk_manager.delete_snapshot(snapshot_id)
          end
          @logger.info("The snapshot '#{snapshot_id}' is deleted")
        end
      end
    end

    ##
    # The recommended implementation is to raise Bosh::Clouds::NotSupported error. This method will be deprecated in API v2.
    # After the Director received NotSupported error, it will delete the VM (via delete_vm) and create a new VM with desired network configuration (via create_vm).
    #
    # @param [String] vm_cid   Cloud ID of the VM to modify; returned from create_vm.
    # @param [Hash]   networks Network hashes that specify networks VM must be configured.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/configure-networks/
    #
    def configure_networks(vm_cid, networks)
      @logger.info("configure_networks(#{vm_cid}, #{networks})")
      # Azure does not support to configure the network of an existing VM,
      # so we need to notify the InstanceUpdater to recreate it
      raise Bosh::Clouds::NotSupported
    end

    ##
    # Determines cloud ID of the VM executing the CPI code. Currently used in combination with get_disks by the Director to determine which disks to self-snapshot.
    # Do not implement; this method will be deprecated and removed.
    #
    # @return [String] vm_cid Cloud ID of the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/current-vm-id/
    #
    def current_vm_id
      @logger.info('current_vm_id')
      raise Bosh::Clouds::NotSupported
    end

    private

    def _azure_config
      @config.azure
    end

    def _init_registry
      # Registry updates are not really atomic in relation to
      # Azure API calls, so they might get out of sync.
      # As of CPI API v2, the registry is optional (when stemcell API version is suitable)
      @registry = Bosh::Cpi::RegistryClient.new(@config.registry.endpoint, @config.registry.user, @config.registry.password)
    end

    def _init_azure
      # get the default storage account.
      @azure_client            = Bosh::AzureCloud::AzureClient.new(_azure_config, @logger)
      @blob_manager            = Bosh::AzureCloud::BlobManager.new(_azure_config, @azure_client)
      @disk_manager            = Bosh::AzureCloud::DiskManager.new(_azure_config, @blob_manager)
      @storage_account_manager = Bosh::AzureCloud::StorageAccountManager.new(_azure_config, @blob_manager, @azure_client)

      table_manager            = Bosh::AzureCloud::TableManager.new(_azure_config, @storage_account_manager, @azure_client)
      @meta_store              = Bosh::AzureCloud::MetaStore.new(table_manager)

      @stemcell_manager        = Bosh::AzureCloud::StemcellManager.new(@blob_manager, @meta_store, @storage_account_manager)
      @disk_manager2           = Bosh::AzureCloud::DiskManager2.new(@azure_client)
      @stemcell_manager2       = Bosh::AzureCloud::StemcellManager2.new(@blob_manager, @meta_store, @storage_account_manager, @azure_client)
      @light_stemcell_manager  = Bosh::AzureCloud::LightStemcellManager.new(@blob_manager, @storage_account_manager, @azure_client)
      @config_disk_manager     = Bosh::AzureCloud::ConfigDiskManager.new(@blob_manager, @disk_manager2, @storage_account_manager)
      @vm_manager              = Bosh::AzureCloud::VMManager.new(_azure_config, @registry.endpoint, @disk_manager, @disk_manager2, @azure_client, @storage_account_manager, @stemcell_manager, @stemcell_manager2, @light_stemcell_manager, @config_disk_manager)
      @instance_type_mapper    = Bosh::AzureCloud::InstanceTypeMapper.new
    rescue Net::OpenTimeout => e
      cloud_error("Please make sure the CPI has proper network access to Azure. #{e.inspect}") # TODO: Will it throw the error when initializing the client and manager
    end

    def _init_cpi_lock_dir
      @logger.info('_init_cpi_lock_dir: Initializing the CPI lock directory')
      FileUtils.mkdir_p(CPI_LOCK_DIR)
    end

    def _update_agent_settings(instance_id)
      raise ArgumentError, 'block is not provided' unless block_given?

      settings = registry.read_settings(instance_id)
      yield settings
      registry.update_settings(instance_id, settings)
    end

    def _create_vm_response(instance_id, networks)
      @api_version > 1 ? [instance_id, networks] : instance_id
    end

    def _attach_disk_response(disk_hints)
      disk_hints if @api_version > 1
    end

    def _should_write_to_registry?
      @stemcell_api_version < STEMCELL_API_VERSION_REGISTRYLESS || @api_version < API_VERSION_REGISTRYLESS
    end
  end
end
