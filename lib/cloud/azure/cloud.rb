module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_reader   :registry
    attr_reader   :options
    attr_reader   :azure

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
      @azure = Bosh::AzureCloud::AzureClient.new(azure_properties, @registry.endpoint)
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
        @azure.stemcell_manager.create_stemcell(image_path, cloud_properties)
      end
    end

    ##
    # Deletes a stemcell
    #
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @return [void]
    def delete_stemcell(stemcell_id)
      with_thread_name("delete_stemcell(#{stemcell_id})") do
        @azure.stemcell_manager.delete_stemcell(stemcell_id)
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
    #  {"instance_type" => "Small"}
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
        unless @azure.stemcell_manager.has_stemcell?(stemcell_id)
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell '#{stemcell_id}' does not exist"
        end

        stemcell_uri = @azure.stemcell_manager.get_stemcell_uri(stemcell_id)
        instance_id = @azure.vm_manager.create(
          agent_id,
          stemcell_uri,
          azure_properties,
          NetworkConfigurator.new(networks),
          resource_pool)
        @logger.info("Created new vm '#{instance_id}'")

        begin
          registry_settings = initial_agent_settings(
            agent_id,
            instance_id,
            networks,
            env,
            "/dev/sda"
          )
          registry.update_settings(instance_id, registry_settings)

          instance_id
        rescue => e
          @logger.error(%Q[Failed to update registry after new vm was created: #{e.message}\n#{e.backtrace.join("\n")}])
          @azure.vm_manager.delete(instance_id) if instance_id
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
        @azure.vm_manager.delete(instance_id)
      end
    end

    ##
    # Checks if a VM exists
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @return [Boolean] True if the vm exists
    def has_vm?(instance_id)
      with_thread_name("has_vm?(#{instance_id})") do
        vm = @azure.vm_manager.find(instance_id)
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
        @azure.disk_manager.has_disk?(disk_id)
      end
    end

    ##
    # Reboots a VM
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Optional, Hash] options CPI specific options (e.g hard/soft reboot)
    # @return [void]
    def reboot_vm(instance_id, options=nil)
      with_thread_name("reboot_vm(#{instance_id})") do
        @azure.vm_manager.reboot(instance_id)
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
      @azure.vm_manager.set_metadata(instance_id, encode_metadata(metadata))
    end

    ##
    # Configures networking an existing VM.
    #
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [Hash] networks list of networks and their settings needed for this VM,
    #               same as the networks argument in {#create_vm}
    # @return [void]
    def configure_networks(instance_id, networks)
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
      with_thread_name("create_disk(#{size})") do
        @logger.info("Create disk for vm #{instance_id}") unless instance_id.nil?
        validate_disk_size(size)

        @azure.disk_manager.create_disk(size/1024)
      end
    end

    def validate_disk_size(size)
      raise ArgumentError, 'disk size needs to be an integer' unless size.kind_of?(Integer)

      cloud_error('Azure CPI minimum disk size is 1 GiB') if size < 1024
      cloud_error('Azure CPI maximum disk size is 1 TiB') if size > 1024 * 1000
    end

    ##
    # Deletes a disk
    # Will raise an exception if the disk is attached to a VM
    #
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def delete_disk(disk_id)
      with_thread_name("delete_disk(#{disk_id})") do
        @azure.disk_manager.delete_disk(disk_id)
      end
    end

    # Attaches a disk
    # @param [String] instance_id Instance id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def attach_disk(instance_id, disk_id)
      with_thread_name("attach_disk(#{instance_id},#{disk_id})") do
        volume_name = @azure.vm_manager.attach_disk(instance_id, disk_id)

        update_agent_settings(instance_id) do |settings|
          settings["disks"] ||= {}
          settings["disks"]["persistent"] ||= {}
          settings["disks"]["persistent"][disk_id] = volume_name
        end

        @logger.info("Attached `#{disk_id}' to `#{instance_id}'")
      end
    end

    # Take snapshot of disk
    # @param [String] disk_id disk id of the disk to take the snapshot of
    # @param [Hash] metadata metadata key/value pairs
    # @return [String] snapshot id
    def snapshot_disk(disk_id, metadata={})
      with_thread_name("snapshot_disk(#{disk_id},#{metadata})") do
        snapshot_id = @azure.disk_manager.snapshot_disk(disk_id, encode_metadata(metadata))

        @logger.info("Take a snapshot disk '#{snapshot_id}' for '#{disk_id}'")
        snapshot_id
      end
    end

    # Delete a disk snapshot
    # @param [String] snapshot_id snapshot id to delete
    # @return [void]
    def delete_snapshot(snapshot_id)
      with_thread_name("delete_snapshot(#{snapshot_id})") do
        @azure.disk_manager.delete_disk(snapshot_id)
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

        @azure.vm_manager.detach_disk(instance_id, disk_id)

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
        vm = @azure.vm_manager.find(instance_id)
        raise Bosh::Clouds::VMNotFound, "VM '#{instance_id}' cannot be found" if vm.nil?
        vm[:data_disks].each do |disk|
          disks << disk[:name]
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
            "storage_access_key",
            "resource_group_name",
            "ssh_user",
            "ssh_certificate",
            "tenant_id",
            "client_id",
            "client_secret"],
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
      @registry = Bosh::Registry::Client.new(registry_endpoint,
                                             registry_user,
                                             registry_password)
    end

    # Generates initial agent settings. These settings will be read by agent
    # from AZURE registry (also a BOSH component) on a target instance. Disk
    # conventions for Azure are:
    # system disk: /dev/sda
    # ephemeral disk: /dev/sdb
    #
    # @param [String] agent_id Agent id (will be picked up by agent to
    #   assume its identity
    # @param [String] vm_name VM name
    # @param [Hash] network_spec Agent network spec
    # @param [Hash] environment
    # @param [String] root_device_name root device, e.g. /dev/sda1
    # @return [Hash]
    def initial_agent_settings(agent_id, vm_name, network_spec, environment, root_device_name)
      settings = {
          "vm" => {
              "name" => vm_name
          },
          "agent_id" => agent_id,
          "networks" => network_spec,
          "disks" => {
              "system" => root_device_name,
              "ephemeral" => "/dev/sdb",
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
  end
end
