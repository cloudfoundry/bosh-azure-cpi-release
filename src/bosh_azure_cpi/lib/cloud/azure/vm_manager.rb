module Bosh::AzureCloud
  class VMManager
    include Helpers

    def initialize(azure_properties, registry_endpoint, disk_manager, disk_manager2, azure_client2)
      @azure_properties = azure_properties
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @disk_manager2 = disk_manager2
      @azure_client2 = azure_client2
      @use_managed_disks = @azure_properties['use_managed_disks']
      @logger = Bosh::Clouds::Config.logger
    end

    def create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
      # network_configurator contains service principal in azure_properties so we must not log it.
      @logger.info("create(#{instance_id}, #{location}, #{stemcell_info.inspect}, #{resource_pool}, ..., ...)")

      vm_size = resource_pool.fetch('instance_type', nil)
      cloud_error("missing required cloud property `instance_type'.") if vm_size.nil?

      network_interfaces = create_network_interfaces(instance_id, location, resource_pool, network_configurator)
      availability_set = create_availability_set(location, resource_pool, env)

      @disk_manager.resource_pool = resource_pool
      @disk_manager2.resource_pool = resource_pool

      # Raise errors if the properties are not valid before doing others.
      if @use_managed_disks
        os_disk = @disk_manager2.os_disk(instance_id, stemcell_info.disk_size)
        ephemeral_disk = @disk_manager2.ephemeral_disk(instance_id)
      else
        os_disk = @disk_manager.os_disk(instance_id, stemcell_info.disk_size)
        ephemeral_disk = @disk_manager.ephemeral_disk(instance_id)
      end

      vm_params = {
        :name                => instance_id,
        :location            => location,
        :tags                => AZURE_TAGS,
        :vm_size             => vm_size,
        :os_disk             => os_disk,
        :ephemeral_disk      => ephemeral_disk,
        :os_type             => stemcell_info.os_type,
        :managed             => @use_managed_disks
      }
      if stemcell_info.is_light_stemcell?
        vm_params[:image_reference] = stemcell_info.image_reference
      else
        if @use_managed_disks
          vm_params[:image_id] = stemcell_info.uri
        else
          vm_params[:image_uri] = stemcell_info.uri
        end
      end

      case stemcell_info.os_type
      when 'linux'
        vm_params[:ssh_username]  = @azure_properties['ssh_user']
        vm_params[:ssh_cert_data] = @azure_properties['ssh_public_key']
        vm_params[:custom_data]   = get_user_data(instance_id, network_configurator.default_dns)
      when 'windows'
        # Generate secure random strings as username and password for Windows VMs
        # Users do not use this credential to logon to Windows VMs
        # If users want to logon to Windows VMs, they need to add a new user via the job `user_add'
        # https://github.com/cloudfoundry/bosh-deployment/blob/master/jumpbox-user.yml
        #
        # https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines/virtualmachines-create-or-update
        # adminUsername:
        #   Max-length (Windows): 20 characters
        vm_params[:windows_username] = SecureRandom.uuid.delete('-')[0,20]
        # adminPassword:
        #   Minimum-length (Windows): 8 characters
        #   Max-length (Windows): 123 characters
        #   Complexity requirements: 3 out of 4 conditions below need to be fulfilled
        #     Has lower characters
        #     Has upper characters
        #     Has a digit
        #     Has a special character (Regex match [\W_])
        vm_params[:windows_password] = "#{SecureRandom.uuid}#{SecureRandom.uuid.upcase}".split('').shuffle.join
        computer_name = generate_windows_computer_name()
        vm_params[:computer_name] = computer_name
        vm_params[:custom_data]   = get_user_data(instance_id, network_configurator.default_dns, computer_name)
      end

      create_virtual_machine(vm_params, network_interfaces, availability_set)

      vm_params
    rescue => e
      error_message = ''
      if @keep_failed_vm
        # Including undeleted resources in error message to ask users to delete them manually later
        error_message = 'This VM fails in provisioning after multiple retries.\n'
        error_message += 'You need to delete below resource manually after finishing investigation.\n'
        error_message += "\t Virtual Machine: #{instance_id}\n"
        if @use_managed_disks
          os_disk_name = @disk_manager2.generate_os_disk_name(instance_id)
          error_message += "\t Managed OS Disk: #{os_disk_name}\n"

          unless vm_params[:ephemeral_disk].nil?
            ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(instance_id)
            error_message += "\t Managed Ephemeral Disk: #{ephemeral_disk_name}\n"
          end
        else
          storage_account_name = get_storage_account_name_from_instance_id(instance_id)
          os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
          error_message += "\t OS disk blob: #{os_disk_name}.vhd in the container #{DISK_CONTAINER} in the storage account #{storage_account_name}\n"

          unless vm_params[:ephemeral_disk].nil?
            ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(instance_id)
            error_message += "\t Ephemeral disk blob: #{ephemeral_disk_name}.vhd in the container #{DISK_CONTAINER} in the storage account #{storage_account_name}\n"
          end

          error_message += "\t VM status blobs: All blobs which matches the pattern /^#{instance_id}.*status$/ in the container #{DISK_CONTAINER} in the storage account #{storage_account_name}\n"
        end
      else
        begin
          if network_interfaces
            network_interfaces.each do |network_interface|
              @azure_client2.delete_network_interface(network_interface[:name])
            end
          else
            delete_possible_network_interfaces(instance_id)
          end

          dynamic_public_ip = @azure_client2.get_public_ip_by_name(instance_id)
          @azure_client2.delete_public_ip(instance_id) unless dynamic_public_ip.nil?
        rescue => error
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
      @azure_client2.get_virtual_machine_by_name(instance_id)
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      vm = @azure_client2.get_virtual_machine_by_name(instance_id)
      unless vm.nil?
        @azure_client2.delete_virtual_machine(instance_id)
        vm[:network_interfaces].each do |network_interface|
          @azure_client2.delete_network_interface(network_interface[:name])
        end
      else
        delete_possible_network_interfaces(instance_id)
      end

      dynamic_public_ip = @azure_client2.get_public_ip_by_name(instance_id)
      @azure_client2.delete_public_ip(instance_id) unless dynamic_public_ip.nil?

      if @use_managed_disks
        os_disk_name = @disk_manager2.generate_os_disk_name(instance_id)
        @disk_manager2.delete_disk(os_disk_name)

        ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(instance_id)
        @disk_manager2.delete_disk(ephemeral_disk_name)
      else
        os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
        @disk_manager.delete_disk(os_disk_name)

        ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(instance_id)
        @disk_manager.delete_disk(ephemeral_disk_name)

        # Cleanup invalid VM status file
        storage_account_name = get_storage_account_name_from_instance_id(instance_id)
        @disk_manager.delete_vm_status_files(storage_account_name, instance_id)
      end
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      @azure_client2.restart_virtual_machine(instance_id)
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      @azure_client2.update_tags_of_virtual_machine(instance_id, metadata.merge(AZURE_TAGS))
    end

    ##
    # Attach a disk to the Vm
    #
    # @param [String] instance_id Instance id
    # @param [String] disk_name disk name
    # @return [String] lun
    def attach_disk(instance_id, disk_name)
      @logger.info("attach_disk(#{instance_id}, #{disk_name})")
      if @use_managed_disks && is_managed_vm?(instance_id)
        disk_params = {
          :disk_name => disk_name,
          :caching   => @disk_manager2.get_data_disk_caching(disk_name),
          :disk_id   => @azure_client2.get_managed_disk_by_name(disk_name)[:id],
          :managed   => true
        }
        disk = @azure_client2.attach_disk_to_virtual_machine(instance_id, disk_params)
      else
        disk_params = {
          :disk_name => disk_name,
          :caching   => @disk_manager.get_data_disk_caching(disk_name),
          :disk_uri  => @disk_manager.get_disk_uri(disk_name),
          :disk_size => @disk_manager.get_disk_size_in_gb(disk_name),
          :managed   => false
        }
        disk = @azure_client2.attach_disk_to_virtual_machine(instance_id, disk_params)
      end
      "#{disk[:lun]}"
    end

    def detach_disk(instance_id, disk_name)
      @logger.info("detach_disk(#{instance_id}, #{disk_name})")
      @azure_client2.detach_disk_from_virtual_machine(instance_id, disk_name)
    end

    private

    # Example -
    # For Linux:     {"registry":{"endpoint":"http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"},"server":{"name":"<instance-id>"},"dns":{"nameserver":["168.63.129.16","8.8.8.8"]}}
    # For Windows:   {"registry":{"endpoint":"http://registry:ba42b9e9-fe2c-4d7d-47fb-3eeb78ff49b1@127.0.0.1:6901"},"instance-id":"<instance-id>","server":{"name":"<randomgeneratedname>"},"dns":{"nameserver":["168.63.129.16","8.8.8.8"]}}
    def get_user_data(vm_name, dns, computer_name = nil)
      user_data = {registry: {endpoint: @registry_endpoint}}
      if computer_name
        user_data[:'instance-id'] = vm_name
        user_data[:server] = {name: computer_name}
      else
        user_data[:server] = {name: vm_name}
      end
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def get_network_subnet(network)
      subnet = @azure_client2.get_network_subnet_by_name(network.resource_group_name, network.virtual_network_name, network.subnet_name)
      cloud_error("Cannot find the subnet `#{network.virtual_network_name}/#{network.subnet_name}' in the resource group `#{network.resource_group_name}'") if subnet.nil?
      subnet
    end

    def get_network_security_group(resource_pool, network)
      network_security_group = nil
      resource_group_name = network.resource_group_name
      security_group_name = @azure_properties["default_security_group"]
      if !resource_pool["security_group"].nil?
        security_group_name = resource_pool["security_group"]
      elsif !network.security_group.nil?
        security_group_name = network.security_group
      end
      network_security_group = @azure_client2.get_network_security_group_by_name(resource_group_name, security_group_name)
      if network_security_group.nil?
        default_resource_group_name = @azure_properties['resource_group_name']
        if resource_group_name != default_resource_group_name
          @logger.info("Cannot find the network security group `#{security_group_name}' in the resource group `#{resource_group_name}', trying to search it in the resource group `#{default_resource_group_name}'")
          network_security_group = @azure_client2.get_network_security_group_by_name(default_resource_group_name, security_group_name)
        end
      end
      cloud_error("Cannot find the network security group `#{security_group_name}'") if network_security_group.nil?
      network_security_group
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

    def create_network_interfaces(instance_id, location, resource_pool, network_configurator)
      network_interfaces = []
      load_balancer = get_load_balancer(resource_pool)
      public_ip = get_public_ip(network_configurator.vip_network)
      if public_ip.nil? && resource_pool['assign_dynamic_public_ip'] == true
        # create dynamic public ip
        idle_timeout_in_minutes = @azure_properties.fetch('pip_idle_timeout_in_minutes', 4)
        validate_idle_timeout(idle_timeout_in_minutes)
        @azure_client2.create_public_ip(instance_id, location, false, idle_timeout_in_minutes)
        public_ip = @azure_client2.get_public_ip_by_name(instance_id)
      end
      networks = network_configurator.networks
      networks.each_with_index do |network, index|
        security_group = get_network_security_group(resource_pool, network)
        nic_name = "#{instance_id}-#{index}"
        nic_params = {
          :name                => nic_name,
          :location            => location,
          :private_ip          => (network.is_a? ManualNetwork) ? network.private_ip : nil,
          :public_ip           => index == 0 ? public_ip : nil,
          :security_group      => security_group,
          :ipconfig_name       => "ipconfig#{index}"
        }

        subnet = get_network_subnet(network)
        @azure_client2.create_network_interface(nic_params, subnet, AZURE_TAGS, load_balancer)
        network_interfaces.push(@azure_client2.get_network_interface_by_name(nic_name))
      end
      network_interfaces
    end

    def delete_possible_network_interfaces(instance_id)
      network_interfaces = @azure_client2.list_network_interfaces_by_instance_id(instance_id)
      network_interfaces.each do |network_interface|
        @azure_client2.delete_network_interface(network_interface[:name])
      end
    end

    def create_availability_set(location, resource_pool, env)
      availability_set = nil

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

      unless availability_set_name.nil?
        availability_set = @azure_client2.get_availability_set_by_name(availability_set_name)
        if availability_set.nil?
          # In some regions, the max fault domain count of a managed availability set is 2
          avset_params = {
            :name                         => availability_set_name,
            :location                     => location,
            :tags                         => AZURE_TAGS,
            :platform_update_domain_count => resource_pool['platform_update_domain_count'] || 5,
            :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'] || (@use_managed_disks ? 2 : 3),
            :managed                      => @use_managed_disks
          }
          begin
            @logger.debug("create_availability_set - Creating an availability set `#{avset_params[:name]}'")
            @azure_client2.create_availability_set(avset_params)
            availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
          rescue AzureConflictError => e
            @logger.debug("create_availability_set - Another process is creating the same availability set `#{avset_params[:name]}'")
            loop do
              # TODO: has to sleep to avoid throttling
              availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
              break unless availability_set.nil?
            end
          end
        else
          # Update the availability set to a managed one
          if @use_managed_disks && !availability_set[:managed]
            avset_params = {
              :name                         => availability_set[:name],
              :location                     => availability_set[:location],
              :tags                         => AZURE_TAGS,
              :platform_update_domain_count => availability_set[:platform_update_domain_count],
              :platform_fault_domain_count  => availability_set[:platform_fault_domain_count],
              :managed                      => true
            }
            begin
              @logger.debug("create_availability_set - Updating the availability set `#{avset_params[:name]}' to a managed one")
              @azure_client2.create_availability_set(avset_params)
              availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
            rescue AzureConflictError => e
              @logger.debug("create_availability_set - Another process is updating the same availability set `#{avset_params[:name]}'")
              loop do
                # TODO: has to sleep to avoid throttling
                availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
                break unless availability_set[:managed] == @use_managed_disks
              end
            end
          end
        end
      end
      availability_set
    end

    def create_virtual_machine(vm_params, network_interfaces, availability_set)
      instance_id = vm_params[:name]
      provisioning_fail_retries = 2
      retry_count = 0
      begin
        @keep_failed_vm = false
        @azure_client2.create_virtual_machine(vm_params, network_interfaces, availability_set)
      rescue => e
        retry_create = false
        if e.instance_of?(AzureAsynchronousError) && e.status == PROVISIONING_STATE_FAILED
          if (retry_count += 1) <= provisioning_fail_retries
            @logger.info("create_virtual_machine - Retry #{retry_count}: will retry to create the virtual machine #{instance_id} which failed in provisioning")
            retry_create = true
          else
            # Keep failed VM for advanced investigation only if the VM fails in provisioning after multiple retries
            @keep_failed_vm = true
          end
        end

        unless @keep_failed_vm
          begin
            @logger.info("create_virtual_machine - cleanup resources of the failed virtual machine #{instance_id}")
            @azure_client2.delete_virtual_machine(instance_id)
            if @use_managed_disks
              os_disk_name = @disk_manager2.generate_os_disk_name(instance_id)
              @disk_manager2.delete_disk(os_disk_name)
            else
              os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
              @disk_manager.delete_disk(os_disk_name)

              # Cleanup invalid VM status file
              storage_account_name = get_storage_account_name_from_instance_id(instance_id)
              @disk_manager.delete_vm_status_files(storage_account_name, instance_id)
            end

            unless vm_params[:ephemeral_disk].nil?
              if @use_managed_disks
                ephemeral_disk_name = @disk_manager2.generate_ephemeral_disk_name(instance_id)
                @disk_manager2.delete_disk(ephemeral_disk_name)
              else
                ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(instance_id)
                @disk_manager.delete_disk(ephemeral_disk_name)
              end
            end
          rescue => error
            @keep_failed_vm = true
            error_message = 'The VM fails in provisioning but an error is thrown in cleanuping VM, os disk or ephemeral disk before retry.\n'
            error_message += "#{error.inspect}\n#{error.backtrace.join("\n")}"
            raise e, error_message
          end
        end

        retry if retry_create

        raise e
      end
    end
  end
end
