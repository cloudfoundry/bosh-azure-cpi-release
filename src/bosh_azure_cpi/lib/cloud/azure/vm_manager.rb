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
      disk_info = DiskInfo.for(resource_pool['instance_type'])
      ephemeral_disk_size = disk_info.size
      unless resource_pool['ephemeral_disk'].nil?
        unless resource_pool['ephemeral_disk']['size'].nil?
          size = resource_pool['ephemeral_disk']['size']
          validate_disk_size(size)
          ephemeral_disk_size = size/1024
        end
      end

      caching = 'ReadWrite'
      unless resource_pool['caching'].nil?
        caching = resource_pool['caching']
        validate_disk_caching(caching)
      end

      subnet = get_network_subnet(network_configurator)
      network_security_group = get_network_security_group(resource_pool, network_configurator)
      public_ip = get_public_ip(network_configurator)
      load_balancer = get_load_balancer(resource_pool)

      instance_id  = generate_instance_id(storage_account[:name], uuid)

      network_interface = create_network_interface(instance_id, storage_account, network_configurator, public_ip, network_security_group, subnet, load_balancer)
      availability_set = create_availability_set(storage_account, resource_pool)

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
      @azure_client2.delete_network_interface(instance_id) unless network_interface.nil?

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

    def get_network_subnet(network_configurator)
      subnet = nil
      resource_group_name = @azure_properties['resource_group_name']
      resource_group_name = network_configurator.resource_group_name unless network_configurator.resource_group_name.nil?
      virtual_network_name = network_configurator.virtual_network_name
      subnet_name = network_configurator.subnet_name
      subnet = @azure_client2.get_network_subnet_by_name(resource_group_name, virtual_network_name, subnet_name)
      cloud_error("Cannot find the subnet `#{virtual_network_name}/#{subnet_name}' in the resource group `#{resource_group_name}'") if subnet.nil?
      subnet
    end

    def get_network_security_group(resource_pool, network_configurator)
      network_security_group = nil
      resource_group_name = @azure_properties['resource_group_name']
      resource_group_name = network_configurator.resource_group_name unless network_configurator.resource_group_name.nil?
      security_group_name = @azure_properties["default_security_group"]
      if !resource_pool["security_group"].nil?
        security_group_name = resource_pool["security_group"]
      elsif !network_configurator.security_group.nil?
        security_group_name = network_configurator.security_group
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

    def get_public_ip(network_configurator)
      public_ip = nil
      unless network_configurator.vip_network.nil?
        resource_group_name = @azure_properties['resource_group_name']
        resource_group_name = network_configurator.resource_group_name('vip') unless network_configurator.resource_group_name('vip').nil?
        public_ip = @azure_client2.list_public_ips(resource_group_name).find { |ip| ip[:ip_address] == network_configurator.public_ip }
        cloud_error("Cannot find the public IP address `#{network_configurator.public_ip}' in the resource group `#{resource_group_name}'") if public_ip.nil?
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

    def create_network_interface(instance_id, storage_account, network_configurator, public_ip, network_security_group, subnet, load_balancer)
      network_interface = nil
      nic_params = {
        :name                => instance_id,
        :location            => storage_account[:location],
        :private_ip          => network_configurator.private_ip,
        :public_ip           => public_ip,
        :security_group      => network_security_group
      }

      @azure_client2.create_network_interface(nic_params, subnet, AZURE_TAGS, load_balancer)
      network_interface = @azure_client2.get_network_interface_by_name(instance_id)
    end

    def create_availability_set(storage_account, resource_pool)
      availability_set = nil
      unless resource_pool['availability_set'].nil?
        availability_set = @azure_client2.get_availability_set_by_name(resource_pool['availability_set'])
        if availability_set.nil?
          avset_params = {
            :name                         => resource_pool['availability_set'],
            :location                     => storage_account[:location],
            :tags                         => AZURE_TAGS,
            :platform_update_domain_count => resource_pool['platform_update_domain_count'] || 5,
            :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'] || 3
          }
          begin
            @azure_client2.create_availability_set(avset_params)
            availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
          rescue AzureConflictError => e
            @logger.debug("create_availability_set - Another process is creating the same availability set `#{avset_params[:name]}'")
            loop do
              availability_set = @azure_client2.get_availability_set_by_name(avset_params[:name])
              break unless availability_set.nil?
            end
          end
        end
      end
      availability_set
    end
  end
end
