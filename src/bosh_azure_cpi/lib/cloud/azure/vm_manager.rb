module Bosh::AzureCloud
  class VMManager
    include Helpers

    AZURE_TAGS = {'user-agent' => 'bosh'}

    def initialize(azure_properties, registry_endpoint, disk_manager, azure_client2)
      @azure_properties = azure_properties
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @azure_client2 = azure_client2

      @logger = Bosh::Clouds::Config.logger
    end

    def create(uuid, storage_account, stemcell_uri, resource_pool, network_configurator)
      instance_is_created = false
      ephemeral_disk_size = 15
      if resource_pool.has_key?('ephemeral_disk')
        if resource_pool['ephemeral_disk'].has_key?('size')
          size = resource_pool['ephemeral_disk']['size']
          validate_disk_size(size)
          ephemeral_disk_size = size/1024
        end
      end

      subnet = @azure_client2.get_network_subnet_by_name(network_configurator.virtual_network_name, network_configurator.subnet_name)
      raise "Cannot find the subnet #{network_configurator.virtual_network_name}/#{network_configurator.subnet_name}" if subnet.nil?

      security_group_name = @azure_properties["default_security_group"]
      if resource_pool.has_key?("security_group")
        security_group_name = resource_pool["security_group"]
      elsif !network_configurator.security_group.nil?
        security_group_name = network_configurator.security_group
      end
      network_security_group = @azure_client2.get_network_security_group_by_name(security_group_name)
      raise "Cannot find the network security group #{security_group_name}" if network_security_group.nil?

      caching = 'ReadWrite'
      if resource_pool.has_key?('caching')
        caching = resource_pool['caching']
        validate_disk_caching(caching)
      end

      instance_id  = generate_instance_id(storage_account[:name], uuid)

      public_ip = nil
      unless network_configurator.vip_network.nil?
        public_ip = @azure_client2.list_public_ips().find { |ip| ip[:ip_address] == network_configurator.public_ip}
        cloud_error("Cannot find the public IP address #{network_configurator.public_ip}") if public_ip.nil?
      end

      load_balancer = nil
      if resource_pool.has_key?('load_balancer')
        load_balancer = @azure_client2.get_load_balancer_by_name(resource_pool['load_balancer'])
        cloud_error("Cannot find the load balancer #{resource_pool['load_balancer']}") if load_balancer.nil?
      end

      nic_params = {
        :name                => instance_id,
        :location            => storage_account[:location],
        :private_ip          => network_configurator.private_ip,
        :public_ip           => public_ip,
        :security_group      => network_security_group
      }
      network_tags = AZURE_TAGS
      if resource_pool.has_key?('availability_set')
        network_tags = network_tags.merge({'availability_set' => resource_pool['availability_set']})
      end
      @azure_client2.create_network_interface(nic_params, subnet, network_tags, load_balancer)
      network_interface = @azure_client2.get_network_interface_by_name(instance_id)

      availability_set = nil
      if resource_pool.has_key?('availability_set')
        availability_set = @azure_client2.get_availability_set_by_name(resource_pool['availability_set'])
        if availability_set.nil?
          avset_params = {
            :name                         => resource_pool['availability_set'],
            :location                     => storage_account[:location],
            :tags                         => AZURE_TAGS,
            :platform_update_domain_count => resource_pool['platform_update_domain_count'] || 5,
            :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'] || 3
          }
          availability_set = create_availability_set(avset_params)
        end
      end

      os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
      vm_params = {
        :name                => instance_id,
        :location            => storage_account[:location],
        :tags                => AZURE_TAGS,
        :vm_size             => resource_pool['instance_type'],
        :username            => @azure_properties['ssh_user'],
        :custom_data         => get_user_data(instance_id, network_configurator.dns),
        :image_uri           => stemcell_uri,
        :os_disk_name        => os_disk_name,
        :os_vhd_uri          => @disk_manager.get_disk_uri(os_disk_name),
        :caching             => caching,
        :ssh_cert_data       => @azure_properties['ssh_public_key'],
        :ephemeral_disk_name => EPHEMERAL_DISK_NAME,
        :ephemeral_disk_uri  => @disk_manager.get_disk_uri(@disk_manager.generate_ephemeral_disk_name(instance_id)),
        :ephemeral_disk_size => ephemeral_disk_size
      }

      instance_is_created = true
      @azure_client2.create_virtual_machine(vm_params, network_interface, availability_set)

      instance_id
    rescue => e
      if instance_is_created
        @azure_client2.delete_virtual_machine(instance_id)
        ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(instance_id)
        @disk_manager.delete_disk(ephemeral_disk_name)
      end
      delete_availability_set(availability_set[:name]) unless availability_set.nil?
      @azure_client2.delete_network_interface(network_interface[:name]) unless network_interface.nil?
      # Replace vmSize with instance_type because only instance_type exists in the manifest
      error_message = e.inspect
      error_message = error_message.gsub!('vmSize', 'instance_type') if error_message.include?('vmSize')
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{error_message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      @azure_client2.get_virtual_machine_by_name(instance_id)
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      vm = @azure_client2.get_virtual_machine_by_name(instance_id)
      @azure_client2.delete_virtual_machine(instance_id) unless vm.nil?

      load_balancer = @azure_client2.get_load_balancer_by_name(instance_id)
      @azure_client2.delete_load_balancer(instance_id) unless load_balancer.nil?

      network_interface = @azure_client2.get_network_interface_by_name(instance_id)
      unless network_interface.nil?
        if network_interface[:tags].has_key?('availability_set')
          delete_availability_set(network_interface[:tags]['availability_set'])
        end

        @azure_client2.delete_network_interface(instance_id)
      end

      os_disk_name = @disk_manager.generate_os_disk_name(instance_id)
      @disk_manager.delete_disk(os_disk_name)

      ephemeral_disk_name = @disk_manager.generate_ephemeral_disk_name(instance_id)
      @disk_manager.delete_disk(ephemeral_disk_name)

      # Cleanup invalid VM status file
      storage_account_name = get_storage_account_name_from_instance_id(instance_id)
      @disk_manager.delete_vm_status_files(storage_account_name, instance_id)
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
      disk_uri = @disk_manager.get_disk_uri(disk_name)
      caching = @disk_manager.get_data_disk_caching(disk_name)
      disk = @azure_client2.attach_disk_to_virtual_machine(instance_id, disk_name, disk_uri, caching)
      "#{disk[:lun]}"
    end

    def detach_disk(instance_id, disk_name)
      @logger.info("detach_disk(#{instance_id}, #{disk_name})")
      @azure_client2.detach_disk_from_virtual_machine(instance_id, disk_name)
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry_endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(JSON.dump(user_data))
    end

    def create_availability_set(avset_params)
      availability_set = nil
      begin
        @azure_client2.create_availability_set(avset_params)
        availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
      rescue AzureConflictError => e
        @logger.debug("create_availability_set - Another process is creating the same availability set #{avset_params[:name]}")
        loop do
          availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
          break unless availability_set.nil?
        end
      end
      availability_set
    end

    def delete_availability_set(name)
      availability_set = @azure_client2.get_availability_set_by_name(name)
      if !availability_set.nil? && availability_set[:virtual_machines].size == 0
        @azure_client2.delete_availability_set(name)
      end
    end
  end
end
