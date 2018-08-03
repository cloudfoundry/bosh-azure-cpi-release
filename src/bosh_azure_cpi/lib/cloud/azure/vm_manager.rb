# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    include Helpers

    def initialize(azure_properties, registry_endpoint, disk_manager, disk_manager2, azure_client2, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager)
      @azure_properties = azure_properties
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @disk_manager2 = disk_manager2
      @azure_client2 = azure_client2
      @storage_account_manager = storage_account_manager
      @stemcell_manager = stemcell_manager
      @stemcell_manager2 = stemcell_manager2
      @light_stemcell_manager = light_stemcell_manager
      @use_managed_disks = azure_properties['use_managed_disks']
      @logger = Bosh::Clouds::Config.logger
    end

    def create(instance_id, location, stemcell_id, resource_pool, network_configurator, env)
      # network_configurator contains service principal in azure_properties so we must not log it.
      @logger.info("create(#{instance_id}, #{location}, #{stemcell_id}, #{resource_pool}, ..., ...)")

      vm_name = instance_id.vm_name()

      # When both availability_zone and availability_set are specified, raise an error
      cloud_error("Only one of `availability_zone' and `availability_set' is allowed to be configured for the VM but you have configured both.") if !resource_pool['availability_zone'].nil? && !resource_pool['availability_set'].nil?
      zone = resource_pool.fetch('availability_zone', nil)
      unless zone.nil?
        cloud_error("`#{zone}' is not a valid zone. Available zones are: #{AVAILABILITY_ZONES}") unless AVAILABILITY_ZONES.include?(zone.to_s)
      end

      # async task - prepare stemcell. Time consuming works could be:
      #   * create usage image
      #   * copy stemcell to another storage account
      task_get_stemcell_info = Concurrent::Future.execute do
        get_stemcell_info(stemcell_id, resource_pool, location)
      end

      resource_group_name = instance_id.resource_group_name()
      check_resource_group(resource_group_name, location)

      # When availability_zone is specified, VM won't be in any availability set;
      # Otherwise, VM can be in an availability set specified by availability_set or env['bosh']['group']
      availability_set_name = resource_pool['availability_zone'].nil? ? get_availability_set_name(resource_pool, env) : nil

      # async task - prepare network interfaces. Time consuming works could be:
      #   * create dynamic public IP
      #   * create network interfaces
      primary_nic_tags = AZURE_TAGS.dup
      # Store the availability set name in the tags of the NIC
      primary_nic_tags['availability_set'] = availability_set_name unless availability_set_name.nil?
      task_create_network_interfaces = Concurrent::Future.execute do
        create_network_interfaces(resource_group_name, vm_name, location, resource_pool, network_configurator, primary_nic_tags)
      end

      # async task - prepare availability set. Time consuming works could be:
      #   * create availability set
      #   * migrate availability set
      availability_set_params = {
        name: availability_set_name,
        location: location,
        tags: AZURE_TAGS,
        platform_update_domain_count: resource_pool['platform_update_domain_count'] || default_update_domain_count,
        platform_fault_domain_count: resource_pool['platform_fault_domain_count'] || default_fault_domain_count,
        managed: @use_managed_disks
      }
      task_get_or_create_availability_set = Concurrent::Future.execute do
        get_or_create_availability_set(resource_group_name, availability_set_params)
      end

      # async task - prepare storage account for diagnostics
      task_get_diagnostics_storage_account = Concurrent::Future.execute do
        get_diagnostics_storage_account(location)
      end

      # Wait for completion of all async tasks
      # Note: when exception happens in the thread, .wait won't raise the issue, but .value! will.
      task_get_stemcell_info.wait
      task_create_network_interfaces.wait
      task_get_or_create_availability_set.wait
      task_get_diagnostics_storage_account.wait

      stemcell_info = task_get_stemcell_info.value!
      network_interfaces = task_create_network_interfaces.value!
      availability_set = task_get_or_create_availability_set.value!
      diagnostics_storage_account = task_get_diagnostics_storage_account.value!

      # create vm params
      vm_params = {
        name: vm_name,
        location: location,
        tags: get_tags(resource_pool),
        vm_size: resource_pool['instance_type'],
        managed: @use_managed_disks
      }

      zone = resource_pool.fetch('availability_zone', nil)
      unless zone.nil?
        vm_params[:zone] = zone.to_s
      end

      @disk_manager.resource_pool = resource_pool
      @disk_manager2.resource_pool = resource_pool
      if @use_managed_disks
        os_disk = @disk_manager2.os_disk(vm_name, stemcell_info)
        ephemeral_disk = @disk_manager2.ephemeral_disk(vm_name)
      else
        storage_account_name = instance_id.storage_account_name()
        os_disk = @disk_manager.os_disk(storage_account_name, vm_name, stemcell_info)
        ephemeral_disk = @disk_manager.ephemeral_disk(storage_account_name, vm_name)
      end
      vm_params[:os_disk] = os_disk
      vm_params[:ephemeral_disk] = ephemeral_disk

      vm_params[:os_type] = stemcell_info.os_type
      if stemcell_info.is_light_stemcell?
        vm_params[:image_reference] = stemcell_info.image_reference
      elsif @use_managed_disks
        vm_params[:image_id] = stemcell_info.uri
      else
        vm_params[:image_uri] = stemcell_info.uri
      end

      case stemcell_info.os_type
      when 'linux'
        vm_params[:ssh_username]  = @azure_properties['ssh_user']
        vm_params[:ssh_cert_data] = @azure_properties['ssh_public_key']
        vm_params[:custom_data]   = get_user_data(instance_id.to_s, network_configurator.default_dns)
      when 'windows'
        # Generate secure random strings as username and password for Windows VMs
        # Users do not use this credential to logon to Windows VMs
        # If users want to logon to Windows VMs, they need to add a new user via the job `user_add'
        # https://github.com/cloudfoundry/bosh-deployment/blob/master/jumpbox-user.yml
        #
        # https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
        # adminUsername:
        #   Max-length (Windows): 20 characters
        vm_params[:windows_username] = SecureRandom.uuid.delete('-')[0, 20]
        # adminPassword:
        #   Minimum-length (Windows): 8 characters
        #   Max-length (Windows): 123 characters
        #   Complexity requirements: 3 out of 4 conditions below need to be fulfilled
        #     Has lower characters
        #     Has upper characters
        #     Has a digit
        #     Has a special character (Regex match [\W_])
        vm_params[:windows_password] = "#{SecureRandom.uuid}#{SecureRandom.uuid.upcase}".split('').shuffle.join
        computer_name = generate_windows_computer_name
        vm_params[:computer_name] = computer_name
        vm_params[:custom_data]   = get_user_data(instance_id.to_s, network_configurator.default_dns, computer_name)
      end

      vm_params[:diag_storage_uri] = diagnostics_storage_account[:storage_blob_host] unless diagnostics_storage_account.nil?

      create_virtual_machine(instance_id, vm_params, network_interfaces, availability_set)

      vm_params
    rescue StandardError => e
      error_message = ''
      if @keep_failed_vms
        # Including undeleted resources in error message to ask users to delete them manually later
        error_message = 'This VM fails in provisioning after multiple retries.\n'
        error_message += 'You need to delete below resource manually after finishing investigation.\n'
        error_message += "\t Resource Group: #{resource_group_name}\n"
        error_message += "\t Virtual Machine: #{vm_name}\n"
        if @use_managed_disks
          os_disk_name = @disk_manager2.generate_os_disk_name(vm_name)
          error_message += "\t Managed OS Disk: #{os_disk_name}\n"

          unless vm_params[:ephemeral_disk].nil?
            ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(vm_name)
            error_message += "\t Managed Ephemeral Disk: #{ephemeral_disk_name}\n"
          end
        else
          storage_account_name = instance_id.storage_account_name()
          os_disk_name = @disk_manager.generate_os_disk_name(vm_name)
          error_message += "\t OS disk blob: #{os_disk_name}.vhd in the container #{DISK_CONTAINER} in the storage account #{storage_account_name} in default resource group\n"

          unless vm_params[:ephemeral_disk].nil?
            ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(vm_name)
            error_message += "\t Ephemeral disk blob: #{ephemeral_disk_name}.vhd in the container #{DISK_CONTAINER} in the storage account #{storage_account_name} in default resource group\n"
          end

          error_message += "\t VM status blobs: All blobs which matches the pattern /^#{vm_name}.*status$/ in the container #{DISK_CONTAINER} in the storage account #{storage_account_name} in default resource group\n"
        end
      else
        begin
          # Delete NICs
          if network_interfaces
            network_interfaces.each do |network_interface|
              @azure_client2.delete_network_interface(resource_group_name, network_interface[:name])
            end
          else
            # If create_network_interfaces fails for some reason, some of the NICs are created and some are not.
            # CPI need to cleanup these NICs.
            delete_possible_network_interfaces(resource_group_name, vm_name)
          end

          # Delete the dynamic public IP
          dynamic_public_ip = @azure_client2.get_public_ip_by_name(resource_group_name, vm_name)
          @azure_client2.delete_public_ip(resource_group_name, vm_name) unless dynamic_public_ip.nil?
        rescue StandardError => error
          error_message = 'The VM fails in creating but an error is thrown in cleanuping network interfaces or dynamic public IP.\n'
          error_message += "#{error.inspect}\n#{error.backtrace.join("\n")}"
        end
      end

      error_message += e.inspect

      # Replace vmSize with instance_type because only instance_type exists in the manifest
      error_message = error_message.gsub!('vmSize', 'instance_type') if error_message.include?('vmSize')
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{error_message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      @azure_client2.get_virtual_machine_by_name(instance_id.resource_group_name, instance_id.vm_name)
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      resource_group_name = instance_id.resource_group_name()
      vm_name = instance_id.vm_name()
      vm = @azure_client2.get_virtual_machine_by_name(resource_group_name, vm_name)

      # Delete the VM
      if vm
        if vm[:availability_set].nil?
          @azure_client2.delete_virtual_machine(resource_group_name, vm_name)
        else
          availability_set_name = vm[:availability_set][:name]
          flock("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH) do
            @azure_client2.delete_virtual_machine(resource_group_name, vm_name)
          end
        end
      end

      # After VM is deleted, tasks that can be run in parallel are:
      #   * deleting empty availability set
      #   * deleting network interfaces, then deleting dynamic public IP which is bound to them.
      #   * deleting disks (os disk, ephemeral disk)
      tasks = []

      # Delete availability set
      network_interfaces = @azure_client2.list_network_interfaces_by_keyword(resource_group_name, vm_name)
      availability_set_name = nil
      # If the VM is deleted but the availability sets are not deleted due to some reason, BOSH will retry and VM will be nil.
      # CPI needs to get the availability set name from the primary NIC's tags, and delete it.
      if vm
        availability_set_name = vm[:availability_set][:name] unless vm[:availability_set].nil?
      else
        network_interfaces.each do |network_interface|
          availability_set_name = network_interface[:tags]['availability_set'] unless network_interface[:tags]['availability_set'].nil?
        end
      end
      unless availability_set_name.nil?
        tasks.push(
          Concurrent::Future.execute do
            delete_empty_availability_set(resource_group_name, availability_set_name)
          end
        )
      end

      # Delete network interfaces and dynamic public IP
      tasks.push(
        Concurrent::Future.execute do
          delete_possible_network_interfaces(resource_group_name, vm_name)
          # Delete the dynamic public IP
          dynamic_public_ip = @azure_client2.get_public_ip_by_name(resource_group_name, vm_name)
          @azure_client2.delete_public_ip(resource_group_name, vm_name) unless dynamic_public_ip.nil?
        end
      )

      # Delete OS & ephemeral disks
      if instance_id.use_managed_disks?
        tasks.push(
          Concurrent::Future.execute do
            os_disk_name = @disk_manager2.generate_os_disk_name(vm_name)
            @disk_manager2.delete_disk(resource_group_name, os_disk_name)
          end
        )

        tasks.push(
          Concurrent::Future.execute do
            ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(vm_name)
            @disk_manager2.delete_disk(resource_group_name, ephemeral_disk_name)
          end
        )
      else
        storage_account_name = instance_id.storage_account_name()

        tasks.push(
          Concurrent::Future.execute do
            os_disk_name = @disk_manager.generate_os_disk_name(vm_name)
            @disk_manager.delete_disk(storage_account_name, os_disk_name)
          end
        )

        tasks.push(
          Concurrent::Future.execute do
            ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(vm_name)
            @disk_manager.delete_disk(storage_account_name, ephemeral_disk_name)
          end
        )

        # Cleanup invalid VM status file
        tasks.push(
          Concurrent::Future.execute do
            @disk_manager.delete_vm_status_files(storage_account_name, vm_name)
          end
        )
      end

      # when exception happens in thread, .wait will not raise the error, but .wait! will.
      tasks.map(&:wait)
      tasks.map(&:wait!)
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      @azure_client2.restart_virtual_machine(
        instance_id.resource_group_name,
        instance_id.vm_name
      )
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      @azure_client2.update_tags_of_virtual_machine(
        instance_id.resource_group_name,
        instance_id.vm_name,
        metadata.merge(AZURE_TAGS)
      )
    end

    ##
    # Attach a disk to the Vm
    #
    # @param [InstanceId] instance_id Instance id
    # @param [DiskId] disk_id disk id
    # @return [String] lun
    def attach_disk(instance_id, disk_id)
      @logger.info("attach_disk(#{instance_id}, #{disk_id})")
      disk_name = disk_id.disk_name()
      disk_params = if instance_id.use_managed_disks?
                      {
                        disk_name: disk_name,
                        caching: disk_id.caching,
                        disk_bosh_id: disk_id.to_s,
                        disk_id: @azure_client2.get_managed_disk_by_name(disk_id.resource_group_name, disk_name)[:id],
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
      lun = @azure_client2.attach_disk_to_virtual_machine(
        instance_id.resource_group_name,
        instance_id.vm_name,
        disk_params
      )
      lun.to_s
    end

    def detach_disk(instance_id, disk_id)
      @logger.info("detach_disk(#{instance_id}, #{disk_id})")
      @azure_client2.detach_disk_from_virtual_machine(
        instance_id.resource_group_name,
        instance_id.vm_name,
        disk_id.disk_name
      )
    end

    private

    def get_stemcell_info(stemcell_id, resource_pool, location)
      stemcell_info = nil
      if @use_managed_disks
        storage_account_type = resource_pool['storage_account_type']
        storage_account_type = get_storage_account_type_by_instance_type(resource_pool['instance_type']) if storage_account_type.nil?

        if is_light_stemcell_id?(stemcell_id)
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist" unless @light_stemcell_manager.has_stemcell?(location, stemcell_id)
          stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_id)
        else
          begin
            # Treat user_image_info as stemcell_info
            stemcell_info = @stemcell_manager2.get_user_image_info(stemcell_id, storage_account_type, location)
          rescue StandardError => e
            raise Bosh::Clouds::VMCreationFailed.new(false), "Failed to get the user image information for the stemcell `#{stemcell_id}': #{e.inspect}\n#{e.backtrace.join("\n")}"
          end
        end
      else
        storage_account = @storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)

        if is_light_stemcell_id?(stemcell_id)
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist" unless @light_stemcell_manager.has_stemcell?(location, stemcell_id)
          stemcell_info = @light_stemcell_manager.get_stemcell_info(stemcell_id)
        else
          raise Bosh::Clouds::VMCreationFailed.new(false), "Given stemcell `#{stemcell_id}' does not exist" unless @stemcell_manager.has_stemcell?(storage_account[:name], stemcell_id)
          stemcell_info = @stemcell_manager.get_stemcell_info(storage_account[:name], stemcell_id)
        end
      end

      stemcell_info
    end

    def get_diagnostics_storage_account(location)
      diagnostics_storage_account = nil
      if @azure_properties['enable_vm_boot_diagnostics'] && (@azure_properties['environment'] != ENVIRONMENT_AZURESTACK)
        diagnostics_storage_account = @storage_account_manager.get_or_create_diagnostics_storage_account(location)
      end
      diagnostics_storage_account
    end

    # Example -
    # For Linux:     {"registry":{"endpoint":"http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"},"server":{"name":"<instance-id>"},"dns":{"nameserver":["168.63.129.16","8.8.8.8"]}}
    # For Windows:   {"registry":{"endpoint":"http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"},"instance-id":"<instance-id>","server":{"name":"<randomgeneratedname>"},"dns":{"nameserver":["168.63.129.16","8.8.8.8"]}}
    def get_user_data(instance_id, dns, computer_name = nil)
      user_data = { registry: { endpoint: @registry_endpoint } }
      if computer_name
        user_data[:'instance-id'] = instance_id
        user_data[:server] = { name: computer_name }
      else
        user_data[:server] = { name: instance_id }
      end
      user_data[:dns] = { nameserver: dns } if dns
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def get_network_subnet(network)
      subnet = @azure_client2.get_network_subnet_by_name(network.resource_group_name, network.virtual_network_name, network.subnet_name)
      cloud_error("Cannot find the subnet `#{network.virtual_network_name}/#{network.subnet_name}' in the resource group `#{network.resource_group_name}'") if subnet.nil?
      subnet
    end

    def get_network_security_group(resource_pool, network)
      network_security_group = nil
      # Network security group name can be specified in resource_pool, networks and global configuration (ordered by priority)
      network_security_group_name = resource_pool.fetch('security_group', network.security_group)
      network_security_group_name = @azure_properties['default_security_group'] if network_security_group_name.nil?
      return nil if network_security_group_name.nil?
      cloud_error('Cannot specify an empty string to the network security group') if network_security_group_name.empty?
      # The resource group which the NSG belongs to can be specified in networks and global configuration (ordered by priority)
      resource_group_name = network.resource_group_name
      network_security_group = @azure_client2.get_network_security_group_by_name(resource_group_name, network_security_group_name)
      # network.resource_group_name may return the default resource group name in global configurations. See network.rb.
      default_resource_group_name = @azure_properties['resource_group_name']
      if network_security_group.nil? && resource_group_name != default_resource_group_name
        @logger.info("Cannot find the network security group `#{network_security_group_name}' in the resource group `#{resource_group_name}', trying to search it in the default resource group `#{default_resource_group_name}'")
        network_security_group = @azure_client2.get_network_security_group_by_name(default_resource_group_name, network_security_group_name)
      end
      cloud_error("Cannot find the network security group `#{network_security_group_name}'") if network_security_group.nil?
      network_security_group
    end

    def get_application_security_groups(resource_pool, network)
      application_security_groups = []
      # Application security group name can be specified in resource_pool and networks (ordered by priority)
      application_security_group_names = resource_pool.fetch('application_security_groups', network.application_security_groups)
      application_security_group_names.each do |application_security_group_name|
        # The resource group which the ASG belongs to can be specified in networks and global configuration (ordered by priority)
        resource_group_name = network.resource_group_name
        application_security_group = @azure_client2.get_application_security_group_by_name(resource_group_name, application_security_group_name)
        # network.resource_group_name may return the default resource group name in global configurations. See network.rb.
        default_resource_group_name = @azure_properties['resource_group_name']
        if application_security_group.nil? && resource_group_name != default_resource_group_name
          @logger.info("Cannot find the application security group `#{application_security_group_name}' in the resource group `#{resource_group_name}', trying to search it in the default resource group `#{default_resource_group_name}'")
          application_security_group = @azure_client2.get_application_security_group_by_name(default_resource_group_name, application_security_group_name)
        end
        cloud_error("Cannot find the application security group `#{application_security_group_name}'") if application_security_group.nil?
        application_security_groups.push(application_security_group)
      end
      application_security_groups
    end

    def get_ip_forwarding(resource_pool, network)
      ip_forwarding = false
      # ip_forwarding can be specified in resource_pool and networks (ordered by priority)
      ip_forwarding = resource_pool.fetch('ip_forwarding', network.ip_forwarding)
      ip_forwarding
    end

    def get_accelerated_networking(resource_pool, network)
      accelerated_networking = false
      # accelerated_networking can be specified in resource_pool and networks (ordered by priority)
      accelerated_networking = resource_pool.fetch('accelerated_networking', network.accelerated_networking)
      accelerated_networking
    end

    def get_public_ip(vip_network)
      public_ip = nil
      unless vip_network.nil?
        resource_group_name = vip_network.resource_group_name
        public_ip = @azure_client2.list_public_ips(resource_group_name).find { |ip| ip[:ip_address] == vip_network.public_ip }
        cloud_error("Cannot find the public IP address `#{vip_network.public_ip}' in the resource group `#{resource_group_name}'") if public_ip.nil?
      end
      public_ip
    end

    def get_load_balancer(resource_pool)
      load_balancer = nil
      unless resource_pool['load_balancer'].nil?
        load_balancer_name = resource_pool['load_balancer']
        load_balancer = @azure_client2.get_load_balancer_by_name(load_balancer_name)
        cloud_error("Cannot find the load balancer `#{load_balancer_name}'") if load_balancer.nil?
      end
      load_balancer
    end

    def get_application_gateway(resource_pool)
      application_gateway = nil
      unless resource_pool['application_gateway'].nil?
        application_gateway_name = resource_pool['application_gateway']
        application_gateway = @azure_client2.get_application_gateway_by_name(application_gateway_name)
        cloud_error("Cannot find the application gateway `#{application_gateway_name}'") if application_gateway.nil?
      end
      application_gateway
    end

    def get_or_create_public_ip(resource_group_name, vm_name, location, resource_pool, network_configurator)
      public_ip = get_public_ip(network_configurator.vip_network)
      if public_ip.nil? && resource_pool['assign_dynamic_public_ip'] == true
        # create dynamic public ip
        idle_timeout_in_minutes = @azure_properties.fetch('pip_idle_timeout_in_minutes', 4)
        validate_idle_timeout(idle_timeout_in_minutes)
        public_ip_params = {
          name: vm_name,
          location: location,
          is_static: false,
          idle_timeout_in_minutes: idle_timeout_in_minutes
        }
        public_ip_params[:zone] = resource_pool['availability_zone'].to_s unless resource_pool['availability_zone'].nil?
        @azure_client2.create_public_ip(resource_group_name, public_ip_params)
        public_ip = @azure_client2.get_public_ip_by_name(resource_group_name, vm_name)
      end
      public_ip
    end

    def create_network_interfaces(resource_group_name, vm_name, location, resource_pool, network_configurator, primary_nic_tags = AZURE_TAGS)
      network_interfaces = []

      task_get_or_create_public_ip = Concurrent::Future.execute do
        get_or_create_public_ip(resource_group_name, vm_name, location, resource_pool, network_configurator)
      end
      task_get_load_balancer = Concurrent::Future.execute do
        get_load_balancer(resource_pool)
      end
      task_get_application_gateway = Concurrent::Future.execute do
        get_application_gateway(resource_pool)
      end

      task_get_or_create_public_ip.wait
      task_get_load_balancer.wait
      task_get_application_gateway.wait

      public_ip = task_get_or_create_public_ip.value!
      load_balancer = task_get_load_balancer.value!
      application_gateway = task_get_application_gateway.value!

      tasks = []
      networks = network_configurator.networks
      networks.each_with_index do |network, index|
        network_security_group = get_network_security_group(resource_pool, network)
        application_security_groups = get_application_security_groups(resource_pool, network)
        ip_forwarding = get_ip_forwarding(resource_pool, network)
        accelerated_networking = get_accelerated_networking(resource_pool, network)
        nic_name = "#{vm_name}-#{index}"
        nic_params = {
          name: nic_name,
          location: location,
          private_ip: network.is_a?(ManualNetwork) ? network.private_ip : nil,
          network_security_group: network_security_group,
          application_security_groups: application_security_groups,
          ipconfig_name: "ipconfig#{index}",
          enable_ip_forwarding: ip_forwarding,
          enable_accelerated_networking: accelerated_networking
        }
        nic_params[:subnet] = get_network_subnet(network)
        if index.zero?
          nic_params[:public_ip] = public_ip
          nic_params[:tags] = primary_nic_tags
          nic_params[:load_balancer] = load_balancer
          nic_params[:application_gateway] = application_gateway
        else
          nic_params[:public_ip] = nil
          nic_params[:tags] = AZURE_TAGS
          nic_params[:load_balancer] = nil
          nic_params[:application_gateway] = nil
        end
        tasks.push(
          Concurrent::Future.execute do
            @azure_client2.create_network_interface(resource_group_name, nic_params)
            @azure_client2.get_network_interface_by_name(resource_group_name, nic_name)
          end
        )
      end
      tasks.map(&:wait)
      network_interfaces = tasks.map(&:value!)
    end

    def delete_possible_network_interfaces(resource_group_name, vm_name)
      network_interfaces = @azure_client2.list_network_interfaces_by_keyword(resource_group_name, vm_name)
      tasks = []
      network_interfaces.each do |network_interface|
        tasks.push(
          Concurrent::Future.execute do
            @azure_client2.delete_network_interface(resource_group_name, network_interface[:name])
          end
        )
      end
      tasks.map(&:wait)
      tasks.map(&:wait!)
    end

    def get_availability_set_name(resource_pool, env)
      availability_set_name = resource_pool.fetch('availability_set', nil)
      if availability_set_name.nil?
        unless env.nil? || env['bosh'].nil? || env['bosh']['group'].nil?
          availability_set_name = env['bosh']['group']

          # https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/209
          # On Azure the length of the availability set name must be between 1 and 80 characters.
          # The group name which is generated by BOSH director may be too long.
          # CPI will truncate the name to below format if the length is greater than 80.
          # az-MD5-[LAST-40-CHARACTERS-OF-GROUP]
          if availability_set_name.size > 80
            md = Digest::MD5.hexdigest(availability_set_name)
            availability_set_name = "az-#{md}-#{availability_set_name[-40..-1]}"
          end
        end
      end

      availability_set_name
    end

    def get_tags(resource_pool)
      tags = AZURE_TAGS.dup
      custom_tags = resource_pool.fetch('tags', {})
      tags.merge!(custom_tags)
    end

    # In AzureStack, availability sets can only be configured with 1 fault domain and 1 update domain.
    # In Azure, the max fault domain count of an unmanaged availability set is 3;
    #           the max fault domain count of a managed availability set is 2 in some regions.
    #           When all regions support 3 fault domains, the default value should be changed to 3.
    def default_fault_domain_count
      @azure_properties['environment'] == ENVIRONMENT_AZURESTACK ? 1 : (@use_managed_disks ? 2 : 3)
    end

    # In AzureStack, availability sets can only be configured with 1 update domain.
    # In Azure, the max update domain count of a managed/unmanaged availability set is 5.
    def default_update_domain_count
      @azure_properties['environment'] == ENVIRONMENT_AZURESTACK ? 1 : 5
    end

    def get_or_create_availability_set(resource_group_name, availability_set_params)
      availability_set_name = availability_set_params[:name]
      availability_set = nil
      flock("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX) do
        availability_set = @azure_client2.get_availability_set_by_name(resource_group_name, availability_set_name)
        if availability_set.nil?
          @logger.info("create_availability_set - the availability set `#{availability_set_name}' doesn't exist. Will create a new one.")
          @azure_client2.create_availability_set(resource_group_name, availability_set_params)
          availability_set = @azure_client2.get_availability_set_by_name(resource_group_name, availability_set_name)
        # In some regions, the location of availability set is case-sensitive, e.g. CanadaCentral instead of canadacentral.
        elsif !availability_set[:location].casecmp(availability_set_params[:location]).zero?
          cloud_error("create_availability_set - the availability set `#{availability_set_name}' already exists, but in a different location `#{availability_set[:location].downcase}' instead of `#{availability_set_params[:location].downcase}'. Please delete the availability set or choose another location.")
        elsif !@use_managed_disks && availability_set[:managed]
          cloud_error("create_availability_set - the availability set `#{availability_set_name}' already exists. It's not allowed to update it from managed to unmanaged.")
        elsif @use_managed_disks && !availability_set[:managed]
          @logger.info("create_availability_set - the availability set `#{availability_set_name}' exists, but it needs to be updated from unmanaged to managed.")
          availability_set_params.merge!(
            platform_update_domain_count: availability_set[:platform_update_domain_count],
            platform_fault_domain_count: availability_set[:platform_fault_domain_count],
            managed: true
          )
          @azure_client2.create_availability_set(resource_group_name, availability_set_params)
          availability_set = @azure_client2.get_availability_set_by_name(resource_group_name, availability_set_name)
        else
          @logger.info("create_availability_set - the availability set `#{availability_set_name}' exists. No need to update.")
        end
      end
      cloud_error("get_or_create_availability_set - availability set `#{availability_set_name}' is not created.") if availability_set.nil?
      availability_set
    end

    def delete_empty_availability_set(resource_group_name, availability_set_name)
      flock("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX | File::LOCK_NB) do
        availability_set = @azure_client2.get_availability_set_by_name(resource_group_name, availability_set_name)
        @azure_client2.delete_availability_set(resource_group_name, availability_set_name) if availability_set && availability_set[:virtual_machines].empty?
      end
    end

    def create_virtual_machine(instance_id, vm_params, network_interfaces, availability_set)
      resource_group_name = instance_id.resource_group_name()
      vm_name = instance_id.vm_name()
      max_retries = 2
      retry_create_count = 0
      begin
        @keep_failed_vms = false
        if availability_set.nil?
          @azure_client2.create_virtual_machine(resource_group_name, vm_params, network_interfaces, nil)
        else
          availability_set_name = availability_set[:name]
          flock("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH) do
            @azure_client2.create_virtual_machine(resource_group_name, vm_params, network_interfaces, availability_set)
          end
        end
      rescue StandardError => e
        retry_create = false
        if e.instance_of?(AzureAsynchronousError) && e.status == PROVISIONING_STATE_FAILED
          if (retry_create_count += 1) <= max_retries
            @logger.info("create_virtual_machine - Retry #{retry_create_count}: will retry to create the virtual machine #{vm_name} which failed in provisioning")
            retry_create = true
          else
            # Keep the VM which fails in provisioning after multiple retries if "keep_failed_vms" is true in global configuration
            @keep_failed_vms = @azure_properties['keep_failed_vms']
          end
        end

        unless @keep_failed_vms
          retry_delete_count = 0
          begin
            @logger.info("create_virtual_machine - cleanup resources of the failed virtual machine #{vm_name} from resource group #{resource_group_name}. Retry #{retry_delete_count}.")

            if availability_set
              flock("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set[:name]}", File::LOCK_SH) do
                @azure_client2.delete_virtual_machine(resource_group_name, vm_name)
              end

              # Delete the empty availability set
              delete_empty_availability_set(resource_group_name, availability_set[:name])
            else
              @azure_client2.delete_virtual_machine(resource_group_name, vm_name)
            end

            if @use_managed_disks
              os_disk_name = @disk_manager2.generate_os_disk_name(vm_name)
              @disk_manager2.delete_disk(resource_group_name, os_disk_name)
            else
              storage_account_name = instance_id.storage_account_name()
              os_disk_name = @disk_manager.generate_os_disk_name(vm_name)
              @disk_manager.delete_disk(storage_account_name, os_disk_name)

              # Cleanup invalid VM status file
              @disk_manager.delete_vm_status_files(storage_account_name, vm_name)
            end

            unless vm_params[:ephemeral_disk].nil?
              if @use_managed_disks
                ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(vm_name)
                @disk_manager2.delete_disk(resource_group_name, ephemeral_disk_name)
              else
                ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(vm_name)
                @disk_manager.delete_disk(storage_account_name, ephemeral_disk_name)
              end
            end
          rescue StandardError => error
            retry if (retry_delete_count += 1) <= max_retries
            @keep_failed_vms = true # If the cleanup fails, then the VM resources have to be kept
            error_message = "The VM fails in provisioning.\n"
            error_message += "#{e.inspect}\n#{e.backtrace.join('\n')}\n\n"
            error_message += "And an error is thrown in cleanuping VM, os disk or ephemeral disk before retry.\n"
            error_message += "#{error.inspect}\n#{error.backtrace.join('\n')}"
            raise Bosh::Clouds::CloudError, error_message
          end
        end

        retry if retry_create

        raise e
      end
    end

    def check_resource_group(resource_group_name, location)
      resource_group = @azure_client2.get_resource_group(resource_group_name)
      return true unless resource_group.nil?
      # If resource group does not exist, create it
      @azure_client2.create_resource_group(resource_group_name, location)
    end
  end
end
