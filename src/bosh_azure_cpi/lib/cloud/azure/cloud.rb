# frozen_string_literal: true

module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_reader   :registry
    attr_reader   :config
    # Below defines are for test purpose
    attr_reader   :azure_client, :blob_manager, :meta_store, :storage_account_manager, :vm_manager, :instance_type_mapper
    attr_reader   :disk_manager, :disk_manager2, :stemcell_manager, :stemcell_manager2, :light_stemcell_manager
    attr_reader   :props_factory
    include Helpers

    ##
    # Cloud initialization
    #
    # @param [Hash] options cloud options
    def initialize(options)
      options_dup = options.dup.freeze

      @logger = Bosh::Clouds::Config.logger

      @config = Bosh::AzureCloud::ConfigFactory.build(options_dup)

      request_id = options_dup['azure']['request_id']
      Bosh::AzureCloud::CPILogger.set_request_id(request_id) if request_id

      @use_managed_disks = _azure_config.use_managed_disks

      _init_cpi_lock_dir

      @props_factory = Bosh::AzureCloud::PropsFactory.new(@config)

      @telemetry_manager = Bosh::AzureCloud::TelemetryManager.new(_azure_config)
      @telemetry_manager.monitor('initialize') do
        _init_registry
        _init_azure
      end
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
        extras = {
          'stemcell' => "#{stemcell_properties.fetch('name', 'unknown_name')}-#{stemcell_properties.fetch('version', 'unknown_version')}"
        }
        @telemetry_manager.monitor('create_stemcell', extras: extras) do
          if has_light_stemcell_property?(stemcell_properties)
            @light_stemcell_manager.create_stemcell(stemcell_properties)
          elsif @use_managed_disks
            @stemcell_manager2.create_stemcell(image_path, stemcell_properties)
          else
            @stemcell_manager.create_stemcell(image_path, stemcell_properties)
          end
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
        @telemetry_manager.monitor('delete_stemcell', id: stemcell_id) do
          if is_light_stemcell_id?(stemcell_id)
            @light_stemcell_manager.delete_stemcell(stemcell_id)
          elsif @use_managed_disks
            @stemcell_manager2.delete_stemcell(stemcell_id)
          else
            @stemcell_manager.delete_stemcell(stemcell_id)
          end
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
    #      "cloud_properties" => {
    #        "virtual_network_name"        => "boshvnet",
    #        "subnet_name"                 => "BOSH",
    #        "resource_group_name"         => "rg1",
    #        "security_group"              => "nsg-bosh",
    #        "application_security_groups" => ["asg1", "asg2"],
    #        "ip_forwarding"               => true,
    #        "accelerated_networking"      => true
    #      }
    #    }
    #  }
    #
    # Sample resource pool config (CPI specific):
    #  {"instance_type" => "Standard_D1"}
    #  {
    #    "instance_type" => "Standard_D1",
    #    "root_disk" => {
    #      "size" => 50120, # disk size in MiB
    #    },
    #    "ephemeral_disk" => {
    #      "use_root_disk" => false, # Whether to use OS disk to store the ephemeral data
    #      "size" => 30720, # disk size in MiB
    #    },
    #    # storage_account_name may not exist. The default storage account will be used.
    #    # storage_account_name may be a complete name. It will be used to create the VM.
    #    # storage_account_name may be a pattern '*xxx*'. CPI will filter all storage accounts under the resource group
    #    # by the pattern and pick one storage account which has less than 30 disks to create the VM.
    #    "storage_account_name" => "xxx",
    #    "storage_account_type" => "Standard_LRS",
    #    "storage_account_max_disk_number" => 30,
    #    "availability_zone" => "1",
    #    "availability_set" => "DEA_set",
    #    "platform_update_domain_count" => 5,
    #    "platform_fault_domain_count" => 3,
    #    "resource_group_name" => "rg1",
    #    "assign_dynamic_public_ip" => true,
    #    "security_group" => "nsg-bosh",
    #    "application_security_groups" => ["asg1", "asg2"],
    #    "ip_forwarding" => true,
    #    "accelerated_networking" => true
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
    # @param [Hash] vm_properties cloud specific properties describing the resources needed
    #               for this VM
    # @param [Hash] networks list of networks and their settings needed for this VM
    # @param [optional, String, Array] disk_locality disk name(s) if known of the disk(s) that will be
    #                                    attached to this vm
    # @param [optional, Hash] env environment that will be passed to this vm
    # @return [String] opaque id later used by {#configure_networks}, {#attach_disk},
    #                  {#detach_disk}, and {#delete_vm}
    def create_vm(agent_id, stemcell_id, vm_properties, networks, disk_locality = nil, env = nil)
      # env may contain credentials so we must not log it
      @logger.info("create_vm(#{agent_id}, #{stemcell_id}, #{vm_properties}, #{networks}, #{disk_locality}, ...)")
      with_thread_name("create_vm(#{agent_id}, ...)") do
        vm_props = @props_factory.parse_vm_props(vm_properties)
        # TODO: move the validation into the factory's methods
        cloud_error("missing required cloud property 'instance_type'.") if vm_props.instance_type.nil?
        extras = { 'instance_type' => vm_props.instance_type.nil? ? 'unknown_instance_type' : vm_props.instance_type }
        @telemetry_manager.monitor('create_vm', id: agent_id, extras: extras) do
          # These resources should be in the same location for a VM: VM, NIC, disk(storage account or managed disk).
          # And NIC must be in the same location with VNET, so CPI will use VNET's location as default location for the resources related to the VM.
          network_configurator = NetworkConfigurator.new(_azure_config, networks)
          network = network_configurator.networks[0]
          vnet = @azure_client.get_virtual_network_by_name(network.resource_group_name, network.virtual_network_name)
          cloud_error("Cannot find the virtual network '#{network.virtual_network_name}' under resource group '#{network.resource_group_name}'") if vnet.nil?
          location = vnet[:location]
          location_in_global_configuration = _azure_config.location
          cloud_error("The location in the global configuration '#{location_in_global_configuration}' is different from the location of the virtual network '#{location}'") if !location_in_global_configuration.nil? && location_in_global_configuration != location
          resource_group_name = vm_props.resource_group_name

          if @use_managed_disks
            instance_id = InstanceId.create(resource_group_name, agent_id)
          else
            cloud_error('Virtual Machines deployed to an Availability Zone must use managed disks') unless vm_props.availability_zone.nil?
            storage_account = @storage_account_manager.get_storage_account_from_vm_properties(vm_props, location)
            instance_id = InstanceId.create(resource_group_name, agent_id, storage_account[:name])
          end

          vm_params = @vm_manager.create(
            instance_id,
            location,
            stemcell_id,
            vm_props,
            network_configurator,
            env
          )

          @logger.info("Created new vm '#{instance_id}'")

          begin
            registry_settings = _initial_agent_settings(
              agent_id,
              networks,
              env,
              vm_params
            )
            registry.update_settings(instance_id.to_s, registry_settings)

            instance_id.to_s
          rescue StandardError => e
            @logger.error(%(Failed to update registry after new vm was created: #{e.inspect}\n#{e.backtrace.join("\n")}))
            @vm_manager.delete(instance_id)
            raise e
          end
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
        @telemetry_manager.monitor('delete_vm', id: instance_id) do
          @logger.info("Deleting instance '#{instance_id}'")
          @vm_manager.delete(InstanceId.parse(instance_id, _azure_config.resource_group_name))
        end
      end
    end

    ##
    # Checks if a VM exists
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @return [Boolean] True if the vm exists
    def has_vm?(instance_id)
      with_thread_name("has_vm?(#{instance_id})") do
        @telemetry_manager.monitor('has_vm?', id: instance_id) do
          vm = @vm_manager.find(InstanceId.parse(instance_id, _azure_config.resource_group_name))
          !vm.nil? && vm[:provisioning_state] != 'Deleting'
        end
      end
    end

    ##
    # Checks if a disk exists
    #
    # @param [String] disk disk_id that was once returned by {#create_disk}
    # @return [Boolean] True if the disk exists
    def has_disk?(disk_id)
      with_thread_name("has_disk?(#{disk_id})") do
        @telemetry_manager.monitor('has_disk?', id: disk_id) do
          disk_id = DiskId.parse(disk_id, _azure_config.resource_group_name)
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
    # Reboots a VM
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Optional, Hash] options CPI specific options (e.g hard/soft reboot)
    # @return [void]
    def reboot_vm(instance_id, options = nil)
      with_thread_name("reboot_vm(#{instance_id}, #{options})") do
        @telemetry_manager.monitor('reboot_vm', id: instance_id) do
          @vm_manager.reboot(InstanceId.parse(instance_id, _azure_config.resource_group_name))
        end
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
      @telemetry_manager.monitor('set_vm_metadata', id: instance_id) do
        @logger.info("set_vm_metadata(#{instance_id}, #{metadata})")
        @vm_manager.set_metadata(InstanceId.parse(instance_id, _azure_config.resource_group_name), encode_metadata(metadata))
      end
    end

    ##
    # Map a set of cloud agnostic VM properties (cpu, ram, ephemeral_disk_size) to
    # a set of Azure specific cloud_properties
    #
    # @param  [Hash] vm_resources requested cpu, ram, and ephemeral_disk_size
    # @return [Hash] Azure specific cloud_properties describing instance (e.g. instance_type)
    def calculate_vm_cloud_properties(vm_resources)
      @telemetry_manager.monitor('calculate_vm_cloud_properties') do
        @logger.info("calculate_vm_cloud_properties(#{vm_resources})")
        location = _azure_config.location
        cloud_error("Missing the property 'location' in the global configuration") if location.nil?

        required_keys = %w[cpu ram ephemeral_disk_size]
        missing_keys = required_keys.reject { |key| vm_resources[key] }
        unless missing_keys.empty?
          missing_keys.map! { |k| "'#{k}'" }
          raise "Missing VM cloud properties: #{missing_keys.join(', ')}"
        end

        available_vm_sizes = @azure_client.list_available_virtual_machine_sizes(location)
        instance_type = @instance_type_mapper.map(vm_resources, available_vm_sizes)
        {
          'instance_type' => instance_type,
          'ephemeral_disk' => {
            'size' => (vm_resources['ephemeral_disk_size'] / 1024.0).ceil * 1024
          }
        }
      end
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
        id = instance_id.nil? ? '' : instance_id
        extras = { 'disk_size' => size }
        @telemetry_manager.monitor('create_disk', id: id, extras: extras) do
          validate_disk_size(size)
          disk_id = nil
          if @use_managed_disks
            if instance_id.nil?
              # If instance_id is nil, the managed disk will be created in the resource group location.
              resource_group_name = _azure_config.resource_group_name
              resource_group = @azure_client.get_resource_group(resource_group_name)
              location = resource_group[:location]
              default_storage_account_type = STORAGE_ACCOUNT_TYPE_STANDARD_LRS
              zone = nil
            else
              instance_id = InstanceId.parse(instance_id, _azure_config.resource_group_name)
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
            unless instance_id.nil?
              instance_id = InstanceId.parse(instance_id, _azure_config.resource_group_name)
              @logger.info("Create disk for vm '#{instance_id.vm_name}'")
              storage_account_name = instance_id.storage_account_name
            end
            disk_id = DiskId.create(caching, false, resource_group_name: _azure_config.resource_group_name, storage_account_name: storage_account_name)
            @disk_manager.create_disk(disk_id, size / 1024)
          end
          disk_id.to_s
        end
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
        @telemetry_manager.monitor('delete_disk', id: disk_id) do
          disk_id = DiskId.parse(disk_id, _azure_config.resource_group_name)
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

    # Attaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def attach_disk(instance_id, disk_id)
      with_thread_name("attach_disk(#{instance_id},#{disk_id})") do
        @telemetry_manager.monitor('attach_disk', id: instance_id) do
          instance_id = InstanceId.parse(instance_id, _azure_config.resource_group_name)
          disk_id = DiskId.parse(disk_id, _azure_config.resource_group_name)
          vm_name = instance_id.vm_name
          disk_name = disk_id.disk_name

          vm = @vm_manager.find(instance_id)

          # Workaround for issue #280
          # Issue root cause: Attaching a data disk to a VM whose OS disk is busy might lead to OS hang.
          #                   If 'use_root_disk' is true in 'resource_pools', release packages will be copied to OS disk before attaching data disk,
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
                # migrate only if the disk is an unmanaged disk
                if disk_id.disk_name.start_with?(DATA_DISK_PREFIX)
                  begin
                    storage_account_name = disk_id.storage_account_name
                    blob_uri = @disk_manager.get_data_disk_uri(disk_id)
                    storage_account = @azure_client.get_storage_account_by_name(storage_account_name)
                    location = storage_account[:location]
                    # Can not use the type of the default storage account because only Standard_LRS and Premium_LRS are supported for managed disk.
                    account_type = storage_account[:account_type] == STORAGE_ACCOUNT_TYPE_PREMIUM_LRS ? STORAGE_ACCOUNT_TYPE_PREMIUM_LRS : STORAGE_ACCOUNT_TYPE_STANDARD_LRS
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
              elsif disk[:zone].nil? && !vm_zone.nil? # Only for migration scenario: VM is recreated in a zone while its data disk is still a regional resource.
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

          _update_agent_settings(instance_id.to_s) do |settings|
            settings['disks'] ||= {}
            settings['disks']['persistent'] ||= {}
            settings['disks']['persistent'][disk_id.to_s] = {
              'lun'            => lun,
              'host_device_id' => AZURE_SCSI_HOST_DEVICE_ID,

              # For compatiblity with old stemcells
              'path'           => _get_disk_path_name(lun.to_i)
            }
          end

          @logger.info("Attached the disk '#{disk_id}' to the instance '#{instance_id}', lun '#{lun}'")
        end
      end
    end

    # Detaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def detach_disk(instance_id, disk_id)
      with_thread_name("detach_disk(#{instance_id},#{disk_id})") do
        @telemetry_manager.monitor('detach_disk', id: instance_id) do
          _update_agent_settings(instance_id) do |settings|
            settings['disks'] ||= {}
            settings['disks']['persistent'] ||= {}
            settings['disks']['persistent'].delete(disk_id)
          end

          @vm_manager.detach_disk(
            InstanceId.parse(instance_id, _azure_config.resource_group_name),
            DiskId.parse(disk_id, _azure_config.resource_group_name)
          )

          @logger.info("Detached '#{disk_id}' from '#{instance_id}'")
        end
      end
    end

    # List the attached disks of the VM.
    # @param [String] instance_id is the CPI-standard instance_id (eg, returned from current_vm_id)
    # @return [array[String]] list of opaque disk_ids that can be used with the
    # other disk-related methods on the CPI
    def get_disks(instance_id)
      with_thread_name("get_disks(#{instance_id})") do
        @telemetry_manager.monitor('get_disks', id: instance_id) do
          disks = []
          vm = @vm_manager.find(InstanceId.parse(instance_id, _azure_config.resource_group_name))
          raise Bosh::Clouds::VMNotFound, "VM '#{instance_id}' cannot be found" if vm.nil?
          vm[:data_disks].each do |disk|
            disks << disk[:disk_bosh_id] unless is_ephemeral_disk?(disk[:name])
          end
          disks
        end
      end
    end

    # Take snapshot of disk
    # @param [String] disk_id disk id of the disk to take the snapshot of
    # @param [Hash] metadata metadata key/value pairs
    # @return [String] snapshot id
    def snapshot_disk(disk_id, metadata = {})
      with_thread_name("snapshot_disk(#{disk_id},#{metadata})") do
        @telemetry_manager.monitor('snapshot_disk', id: disk_id) do
          disk_id = DiskId.parse(disk_id, _azure_config.resource_group_name)
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

    # Delete a disk snapshot
    # @param [String] snapshot_id snapshot id to delete
    # @return [void]
    def delete_snapshot(snapshot_id)
      with_thread_name("delete_snapshot(#{snapshot_id})") do
        @telemetry_manager.monitor('delete_snapshot', id: snapshot_id) do
          snapshot_id = DiskId.parse(snapshot_id, _azure_config.resource_group_name)
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

    # Information about the CPI
    # @return [Hash] CPI properties
    def info
      @telemetry_manager.monitor('info') do
        {
          'stemcell_formats' => %w[azure-vhd azure-light]
        }
      end
    end

    private

    def _azure_config
      @config.azure
    end

    def _init_registry
      # Registry updates are not really atomic in relation to
      # Azure API calls, so they might get out of sync.
      @registry = Bosh::Cpi::RegistryClient.new(@config.registry.endpoint, @config.registry.user, @config.registry.password)
    end

    def _init_azure
      @azure_client            = Bosh::AzureCloud::AzureClient.new(_azure_config, @logger)
      @blob_manager            = Bosh::AzureCloud::BlobManager.new(_azure_config, @azure_client)
      @disk_manager            = Bosh::AzureCloud::DiskManager.new(_azure_config, @blob_manager)
      @storage_account_manager = Bosh::AzureCloud::StorageAccountManager.new(_azure_config, @blob_manager, @disk_manager, @azure_client)

      table_manager            = Bosh::AzureCloud::TableManager.new(_azure_config, @storage_account_manager, @azure_client)
      @meta_store              = Bosh::AzureCloud::MetaStore.new(table_manager)

      @stemcell_manager        = Bosh::AzureCloud::StemcellManager.new(@blob_manager, @meta_store, @storage_account_manager)
      @disk_manager2           = Bosh::AzureCloud::DiskManager2.new(@azure_client)
      @stemcell_manager2       = Bosh::AzureCloud::StemcellManager2.new(@blob_manager, @meta_store, @storage_account_manager, @azure_client)
      @light_stemcell_manager  = Bosh::AzureCloud::LightStemcellManager.new(@blob_manager, @storage_account_manager, @azure_client)
      @vm_manager              = Bosh::AzureCloud::VMManager.new(_azure_config, @registry.endpoint, @disk_manager, @disk_manager2, @azure_client, @storage_account_manager, @stemcell_manager, @stemcell_manager2, @light_stemcell_manager)
      @instance_type_mapper    = Bosh::AzureCloud::InstanceTypeMapper.new
    rescue Net::OpenTimeout => e
      cloud_error("Please make sure the CPI has proper network access to Azure. #{e.inspect}") # TODO: Will it throw the error when initializing the client and manager
    end

    def _init_cpi_lock_dir
      @logger.info('_init_cpi_lock_dir: Initializing the CPI lock directory')
      FileUtils.mkdir_p(CPI_LOCK_DIR)
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
    def _initial_agent_settings(agent_id, network_spec, environment, vm_params)
      settings = {
        'vm' => {
          'name' => vm_params[:name]
        },
        'agent_id' => agent_id,
        'networks' => _agent_network_spec(network_spec),
        'disks' => {
          'system' => '/dev/sda',
          'persistent' => {}
        }
      }

      unless vm_params[:ephemeral_disk].nil?
        # Azure uses a data disk as the ephermeral disk and the lun is 0
        settings['disks']['ephemeral'] = {
          'lun'            => '0',
          'host_device_id' => AZURE_SCSI_HOST_DEVICE_ID,

          # For compatiblity with old stemcells
          'path'           => _get_disk_path_name(0)
        }
      end

      settings['env'] = environment if environment
      settings.merge(@config.agent.to_h)
    end

    def _update_agent_settings(instance_id)
      raise ArgumentError, 'block is not provided' unless block_given?

      settings = registry.read_settings(instance_id)
      yield settings
      registry.update_settings(instance_id, settings)
    end

    def _agent_network_spec(network_spec)
      Hash[*network_spec.map do |name, settings|
        settings['use_dhcp'] = true
        [name, settings]
      end.flatten]
    end

    def _get_disk_path_name(lun)
      if (lun + 2) < 26
        "/dev/sd#{('c'.ord + lun).chr}"
      else
        "/dev/sd#{('a'.ord + (lun + 2 - 26) / 26).chr}#{('a'.ord + (lun + 2) % 26).chr}"
      end
    end
  end
end
