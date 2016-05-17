module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_reader   :registry
    attr_reader   :options

    include Helpers

    ##
    # Cloud initialization
    #
    # @param [Hash] options cloud options
    def initialize(options)
      @options = options.dup.freeze
      validate_options

      @logger = Bosh::Clouds::Config.logger

      init_registry
      init_azure
    end

    ##
    # Creates a stemcell
    #
    # @param [String] image_path path to an opaque blob containing the stemcell image
    # @param [Hash] cloud_properties properties required for creating this template
    #               specific to a CPI
    # @return [String] opaque id later used by {#create_vm} and {#delete_stemcell}
    def create_stemcell(image_path, cloud_properties)
      with_thread_name("create_stemcell(#{image_path}...)") do
        @stemcell_manager.create_stemcell(image_path, cloud_properties)
      end
    end

    ##
    # Deletes a stemcell
    #
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @return [void]
    def delete_stemcell(stemcell_id)
      with_thread_name("delete_stemcell(#{stemcell_id})") do
        @stemcell_manager.delete_stemcell(stemcell_id)
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
    #      "cloud_properties" => {"virtual_network_name"=>"boshvnet", "subnet_name"=>"BOSH"}
    #    }
    #  }
    #
    # Sample resource pool config (CPI specific):
    #  {"instance_type" => "Standard_D1"}
    #  {
    #    "instance_type" => "Standard_D1",
    #    "availability_set" => "DEA_set",
    #    "platform_update_domain_count" => 5,
    #    "platform_fault_domain_count" => 3,
    #    "security_group" => "nsg-bosh",
    #    "ephemeral_disk" => {
    #      "size" => 20480, # disk size in MB
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
      with_thread_name("create_vm(#{agent_id}, ...)") do
        unless resource_pool.has_key?('instance_type')
          raise Bosh::Clouds::VMCreationFailed.new(false), "missing required cloud property `instance_type'."
        end

        storage_account = nil
        storage_account_name = @azure_properties['storage_account_name']
        if resource_pool.has_key?('storage_account_name')
          storage_account_name = resource_pool['storage_account_name']
          storage_account = @azure_client2.get_storage_account_by_name(storage_account_name)
          create_storage_account(storage_account_name) if storage_account.nil?
        end

        unless @stemcell_manager.has_stemcell?(storage_account_name, stemcell_id)
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell '#{stemcell_id}' does not exist"
        end

        storage_account = @azure_client2.get_storage_account_by_name(storage_account_name) if storage_account.nil?
        instance_id = @vm_manager.create(
          agent_id,
          storage_account,
          @stemcell_manager.get_stemcell_uri(storage_account_name, stemcell_id),
          resource_pool,
          NetworkConfigurator.new(networks))
        @logger.info("Created new vm '#{instance_id}'")

        begin
          # By default, Azure uses a data disk as the ephermeral disk and the lun is 0
          registry_settings = initial_agent_settings(
            agent_id,
            instance_id,
            networks,
            env,
            "/dev/sda",
            '0'
          )
          registry.update_settings(instance_id, registry_settings)

          instance_id
        rescue => e
          @logger.error(%Q[Failed to update registry after new vm was created: #{e.inspect}\n#{e.backtrace.join("\n")}])
          @vm_manager.delete(instance_id) if instance_id
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
        @logger.info("Deleting instance '#{instance_id}'")
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
    # @param [Integer] size disk size in MB
    # @param [Hash] cloud_properties properties required for creating this disk
    #               specific to a CPI
    # @param [optional, String] instance_id vm id if known of the VM that this disk will
    #                           be attached to
    # @return [String] opaque id later used by {#attach_disk}, {#detach_disk}, and {#delete_disk}
    def create_disk(size, cloud_properties, instance_id = nil)
      with_thread_name("create_disk(#{size}, #{cloud_properties})") do
        storage_account_name = @azure_properties['storage_account_name']
        unless instance_id.nil?
          @logger.info("Create disk for vm #{instance_id}")
          storage_account_name = get_storage_account_name_from_instance_id(instance_id)
        end

        validate_disk_size(size)

        @disk_manager.create_disk(storage_account_name, size/1024, cloud_properties)
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
        @disk_manager.delete_disk(disk_id)
      end
    end

    # Attaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def attach_disk(instance_id, disk_id)
      with_thread_name("attach_disk(#{instance_id},#{disk_id})") do
        lun = @vm_manager.attach_disk(instance_id, disk_id)

        update_agent_settings(instance_id) do |settings|
          settings["disks"] ||= {}
          settings["disks"]["persistent"] ||= {}
          settings["disks"]["persistent"][disk_id] =  {
            'lun'            => lun,
            'host_device_id' => AZURE_SCSI_HOST_DEVICE_ID,

            # For compatiblity with old stemcells
            'path'           => get_disk_path_name(lun.to_i)
          }
        end

        @logger.info("Attached `#{disk_id}' to `#{instance_id}', lun `#{lun}'")
      end
    end

    # Take snapshot of disk
    # @param [String] disk_id disk id of the disk to take the snapshot of
    # @param [Hash] metadata metadata key/value pairs
    # @return [String] snapshot id
    def snapshot_disk(disk_id, metadata = {})
      with_thread_name("snapshot_disk(#{disk_id},#{metadata})") do
        snapshot_id = @disk_manager.snapshot_disk(disk_id, encode_metadata(metadata))

        @logger.info("Take a snapshot disk '#{snapshot_id}' for '#{disk_id}'")
        snapshot_id
      end
    end

    # Delete a disk snapshot
    # @param [String] snapshot_id snapshot id to delete
    # @return [void]
    def delete_snapshot(snapshot_id)
      with_thread_name("delete_snapshot(#{snapshot_id})") do
        @disk_manager.delete_snapshot(snapshot_id)
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
        raise Bosh::Clouds::VMNotFound, "VM '#{instance_id}' cannot be found" if vm.nil?
        vm[:data_disks].each do |disk|
          disks << disk[:name] if disk[:name] != EPHEMERAL_DISK_NAME
        end
        disks
      end
    end

    private

    def agent_properties
      @agent_properties ||= options.fetch('agent', {})
    end

    def azure_properties
      @azure_properties ||= options.fetch('azure')
    end

    ##
    # Checks if options passed to CPI are valid and can actually
    # be used to create all required data structures etc.
    #
    def validate_options
      required_keys = {
          "azure" => ["environment",
            "subscription_id",
            "storage_account_name",
            "resource_group_name",
            "ssh_user",
            "ssh_public_key",
            "tenant_id",
            "client_id",
            "client_secret",
            "default_security_group"],
          "registry" => ["endpoint", "user", "password"],
      }

      missing_keys = []

      required_keys.each_pair do |key, values|
        values.each do |value|
          if !options.has_key?(key) || !options[key].has_key?(value)
            missing_keys << "#{key}:#{value}"
          end
        end
      end

      raise ArgumentError, "missing configuration parameters > #{missing_keys.join(', ')}" unless missing_keys.empty?
    end

    def init_registry
      registry_properties = options.fetch('registry')
      registry_endpoint   = registry_properties.fetch('endpoint')
      registry_user       = registry_properties.fetch('user')
      registry_password   = registry_properties.fetch('password')

      # Registry updates are not really atomic in relation to
      # Azure API calls, so they might get out of sync.
      @registry = Bosh::Cpi::RegistryClient.new(registry_endpoint,
                                             registry_user,
                                             registry_password)
    end

    def init_azure
      @azure_client2    = Bosh::AzureCloud::AzureClient2.new(azure_properties, @logger)
      @blob_manager     = Bosh::AzureCloud::BlobManager.new(azure_properties, @azure_client2)
      @table_manager    = Bosh::AzureCloud::TableManager.new(azure_properties, @azure_client2)
      @stemcell_manager = Bosh::AzureCloud::StemcellManager.new(azure_properties, @blob_manager, @table_manager)
      @disk_manager     = Bosh::AzureCloud::DiskManager.new(azure_properties, @blob_manager)
      @vm_manager       = Bosh::AzureCloud::VMManager.new(azure_properties, @registry.endpoint, @disk_manager, @azure_client2)
    rescue Net::OpenTimeout => e
      cloud_error("Please make sure the CPI has proper network access to Azure. #{e.inspect}")
    end

    # Generates initial agent settings. These settings will be read by agent
    # from AZURE registry (also a BOSH component) on a target instance. Disk
    # conventions for Azure are:
    # system disk: /dev/sda
    # ephemeral disk: data disk at lun 0
    #
    # @param [String] agent_id Agent id (will be picked up by agent to
    #   assume its identity
    # @param [String] vm_name VM name
    # @param [Hash] network_spec Agent network spec
    # @param [Hash] environment
    # @param [String] root_device_name root device, e.g. /dev/sda
    # @param [String] ephemeral_device_lun ephemeral device, e.g. '0'
    # @return [Hash]
    def initial_agent_settings(agent_id, vm_name, network_spec, environment, root_device_name, ephemeral_device_lun)
      settings = {
          "vm" => {
              "name" => vm_name
          },
          "agent_id" => agent_id,
          "networks" => agent_network_spec(network_spec),
          "disks" => {
              "system" => root_device_name,
              "ephemeral" => {
                'lun'            => ephemeral_device_lun,
                'host_device_id' => AZURE_SCSI_HOST_DEVICE_ID,

                # For compatiblity with old stemcells
                'path'           => get_disk_path_name(ephemeral_device_lun.to_i)
              },
              "persistent" => {}
          }
      }

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

    def create_storage_account(storage_account_name)
      @logger.debug("create_storage_account(#{storage_account_name})")
      result = @azure_client2.check_storage_account_name_availability(storage_account_name)
      @logger.debug("create_storage_account - The result of check_storage_account_name_availability is #{result}")
      cloud_error("The storage account name is invalid. #{result[:reason]}: #{result[:message]}") unless result[:available]

      begin
        resource_group = @azure_client2.get_resource_group()
        created = @azure_client2.create_storage_account(storage_account_name, resource_group[:location], 'Standard_RAGRS', {})
        @stemcell_manager.prepare(storage_account_name)
        @disk_manager.prepare(storage_account_name)
        true
      rescue => e
        if created
          msg = "create_storage_account - The storage account is created successfully.\n"
          msg += "But it failed to create the containers bosh and stemcell.\n"
          msg += "You need to manually create them.\n"
          @logger.error(msg)
        end
        raise e
      end
    end

    def get_disk_path_name(lun)
      if((lun + 2) < 26)
        "/dev/sd#{('c'.ord + lun).chr}"
      else
        "/dev/sd#{('a'.ord + (lun + 2 - 26) / 26).chr}#{('a'.ord + (lun + 2) % 26).chr}"
      end
    end
  end
end
