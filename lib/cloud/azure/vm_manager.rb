module Bosh::AzureCloud
  class VMManager
    include Helpers

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

      public_ip = nil
      unless network_configurator.vip_network.nil?
        public_ip = @client2.list_public_ips().find { |ip| ip[:ip_address] == network_configurator.reserved_ip}
        cloud_error("Cannot find the reserved IP address #{network_configurator.reserved_ip}") if public_ip.nil?
      end

      load_balancer = nil
      unless network_configurator.vip_network.nil?
        @client2.create_load_balancer(uuid, public_ip,
                                      network_configurator.tcp_endpoints,
                                      network_configurator.udp_endpoints)
        load_balancer = @client2.get_load_balancer_by_name(uuid)
      end

      nic_params = {
        :name                => uuid,
        :location            => @storage_account[:location],
        :private_ip          => network_configurator.private_ip, 
      }
      @client2.create_network_interface(nic_params, subnet, load_balancer)
      network_interface = @client2.get_network_interface_by_name(uuid)

      instance_id = uuid
      vm_params = {
        :name                => instance_id,
        :location            => @storage_account[:location],
        :vm_size             => resource_pool['instance_type'],
        :username            => cloud_opts['ssh_user'],
        :custom_data         => get_user_data(instance_id, network_configurator.dns),
        :image_uri           => stemcell_uri,
        :os_vhd_uri          => @disk_manager.get_disk_uri("#{instance_id}_os_disk"),
        :ssh_cert_data       => cloud_opts['ssh_certificate']
      }
      @client2.create_virtual_machine(vm_params, network_interface)

      instance_id
    rescue => e
      @client2.delete_virtual_machine(instance_id) unless instance_id.nil?
      @client2.delete_network_interface(network_interface[:name]) unless network_interface.nil?
      @client2.delete_load_balancer(load_balancer[:name]) unless load_balancer.nil?
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{e.message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      @client2.get_virtual_machine_by_name(instance_id)
    rescue => e
      @logger.warn("Cannot find instance by id #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      raise Bosh::Clouds::VMNotFound, "VM `#{instance_id}' not found"
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      vm = find(instance_id)
      @client2.delete_virtual_machine(instance_id)

      network_interface = vm[:network_interface]
      unless network_interface[:load_balancer].nil?
        load_balancer = network_interface[:load_balancer]
        @client2.delete_load_balancer(load_balancer[:name])
      end
      @client2.delete_network_interface(network_interface[:name])

      begin
        @disk_manager.delete_disk(vm[:os_disk][:name])
      rescue => e
        @logger.warn("Cannot delete os disk #{vm[:os_disk][:name]} for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end

      # Cleanup invalid VM status file
      @disk_manager.delete_vm_status_files(instance_id)
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      @client2.restart_virtual_machine(instance_id)
    rescue => e
      @logger.warn("Cannot reboot #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      @client2.update_tags_of_virtual_machine(instance_id, metadata)
    end

    def instance_id(wala_lib_path)
      @logger.debug("instance_id(#{wala_lib_path})")
      contents = File.open(wala_lib_path + "/CustomData", "r"){ |file| file.read }
      user_data = Yajl::Parser.parse(Base64.strict_decode64(contents))

      user_data["server"]["name"]
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
    rescue => e
      raise Bosh::Clouds::DiskNotAttached.new(true),
            "Disk '#{disk_name}' is not attached to instance '#{instance_id}'"
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry_endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(Yajl::Encoder.encode(user_data))
    end
  end
end
