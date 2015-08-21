module Bosh::AzureCloud
  class VMManager
    include Helpers

    OS_DISK_PREFIX = 'bosh-os'
    AZURE_TAGS     = {'user-agent' => 'bosh'}

    def initialize(azure_properties, registry_endpoint, disk_manager)
      @azure_properties = azure_properties
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager

      @logger = Bosh::Clouds::Config.logger
      @client2 = Bosh::AzureCloud::AzureClient2.new(azure_properties, @logger)
      @storage_account = @client2.get_storage_account_by_name(@azure_properties['storage_account_name'])
    end

    def create(uuid, stemcell_uri, cloud_opts, network_configurator, resource_pool)
      subnet = @client2.get_network_subnet_by_name(network_configurator.virtual_network_name, network_configurator.subnet_name)
      raise "Cannot find the subnet #{network_configurator.virtual_network_name}/#{network_configurator.subnet_name}" if subnet.nil?

      load_balancer = nil
      unless network_configurator.vip_network.nil?
        public_ip = @client2.list_public_ips().find { |ip| ip[:ip_address] == network_configurator.public_ip}
        cloud_error("Cannot find the public IP address #{network_configurator.public_ip}") if public_ip.nil?
        @client2.create_load_balancer(uuid, public_ip, AZURE_TAGS,
                                      network_configurator.tcp_endpoints,
                                      network_configurator.udp_endpoints)
        load_balancer = @client2.get_load_balancer_by_name(uuid)
      end

      nic_params = {
        :name                => uuid,
        :location            => @storage_account[:location],
        :private_ip          => network_configurator.private_ip,
      }
      network_tags = AZURE_TAGS
      if resource_pool.has_key?('availability_set')
        network_tags = network_tags.merge({'availability_set' => resource_pool['availability_set']})
      end
      @client2.create_network_interface(nic_params, subnet, network_tags, load_balancer)
      network_interface = @client2.get_network_interface_by_name(uuid)

      availability_set = nil
      if resource_pool.has_key?('availability_set')
        availability_set = @client2.get_availability_set_by_name(resource_pool['availability_set'])
        if availability_set.nil?
          avset_params = {
            :name                         => resource_pool['availability_set'],
            :location                     => @storage_account[:location],
            :tags                         => AZURE_TAGS,
            :platform_update_domain_count => resource_pool['platform_update_domain_count'] || 5,
            :platform_fault_domain_count  => resource_pool['platform_fault_domain_count'] || 3
          }
          @client2.create_availability_set(avset_params)
          availability_set = @client2.get_availability_set_by_name(resource_pool['availability_set'])
        end
      end

      instance_id = uuid
      vm_params = {
        :name                => instance_id,
        :location            => @storage_account[:location],
        :tags                => AZURE_TAGS,
        :vm_size             => resource_pool['instance_type'],
        :username            => cloud_opts['ssh_user'],
        :custom_data         => get_user_data(instance_id, network_configurator.dns),
        :image_uri           => stemcell_uri,
        :os_disk_name        => "#{OS_DISK_PREFIX}-#{instance_id}",
        :os_vhd_uri          => @disk_manager.get_disk_uri("#{OS_DISK_PREFIX}-#{instance_id}"),
        :ssh_cert_data       => cloud_opts['ssh_certificate']
      }
      @client2.create_virtual_machine(vm_params, network_interface, availability_set)

      instance_id
    rescue => e
      @client2.delete_virtual_machine(instance_id) unless instance_id.nil?
      delete_availability_set(availability_set[:name]) unless availability_set.nil?
      @client2.delete_network_interface(network_interface[:name]) unless network_interface.nil?
      @client2.delete_load_balancer(load_balancer[:name]) unless load_balancer.nil?
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{e.message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      @client2.get_virtual_machine_by_name(instance_id)
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      vm = @client2.get_virtual_machine_by_name(instance_id)
      @client2.delete_virtual_machine(instance_id) unless vm.nil?

      load_balancer = @client2.get_load_balancer_by_name(instance_id)
      @client2.delete_load_balancer(instance_id) unless load_balancer.nil?

      network_interface = @client2.get_network_interface_by_name(instance_id)
      unless network_interface.nil?
        if network_interface[:tags].has_key?('availability_set')
          delete_availability_set(network_interface[:tags]['availability_set'])
        end

        @client2.delete_network_interface(instance_id)
      end

      os_disk = "#{OS_DISK_PREFIX}-#{instance_id}"
      @disk_manager.delete_disk(os_disk) if @disk_manager.has_disk?(os_disk)

      # Cleanup invalid VM status file
      @disk_manager.delete_vm_status_files(instance_id)
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      @client2.restart_virtual_machine(instance_id)
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      @client2.update_tags_of_virtual_machine(instance_id, metadata.merge(AZURE_TAGS))
    end

    ##
    # Attach a disk to the Vm
    #
    # @param [String] instance_id Instance id
    # @param [String] disk_name disk name
    # @return [String] volume name. "/dev/sd[c-r]"
    def attach_disk(instance_id, disk_name)
      @logger.info("attach_disk(#{instance_id}, #{disk_name})")
      disk_uri = @disk_manager.get_disk_uri(disk_name)
      disk = @client2.attach_disk_to_virtual_machine(instance_id, disk_name, disk_uri)
      "/dev/sd#{('c'.ord + disk[:lun]).chr}"
    end

    def detach_disk(instance_id, disk_name)
      @logger.info("detach_disk(#{instance_id}, #{disk_name})")
      @client2.detach_disk_from_virtual_machine(instance_id, disk_name)
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry_endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(Yajl::Encoder.encode(user_data))
    end

    def delete_availability_set(name)
      availability_set = @client2.get_availability_set_by_name(name)
      if !availability_set.nil? && availability_set[:virtual_machines].size == 0
        @client2.delete_availability_set(name)
      end
    end
  end
end
