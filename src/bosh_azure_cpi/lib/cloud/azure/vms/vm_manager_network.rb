# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager
    private

    def _get_network_subnet(network)
      subnet = @azure_client.get_network_subnet_by_name(network.resource_group_name, network.virtual_network_name, network.subnet_name)
      cloud_error("Cannot find the subnet '#{network.virtual_network_name}/#{network.subnet_name}' in the resource group '#{network.resource_group_name}'") if subnet.nil?
      subnet
    end

    def _get_network_security_group(vm_props, network)
      # Network security group name can be specified in vm_types or vm_extensions, networks and global configuration (ordered by priority)
      network_security_group_cfg = vm_props.security_group.name.nil? ? network.security_group : vm_props.security_group
      network_security_group_cfg = @azure_config.default_security_group if network_security_group_cfg.name.nil?
      return nil if network_security_group_cfg.name.nil?

      cloud_error('Cannot specify an empty string to the network security group') if network_security_group_cfg.name.empty?

      unless network_security_group_cfg.resource_group_name.nil?
        network_security_group = @azure_client.get_network_security_group_by_name(
          network_security_group_cfg.resource_group_name,
          network_security_group_cfg.name
        )
        cloud_error("Cannot found the security group: #{network_security_group_cfg.name} in the specified resource group: #{network_security_group_cfg.resource_group_name}") if network_security_group.nil?
        return network_security_group
      end

      resource_group_name = network.resource_group_name

      # The resource group which the NSG belongs to can be specified in networks and global configuration (ordered by priority)
      network_security_group = @azure_client.get_network_security_group_by_name(
        resource_group_name,
        network_security_group_cfg.name
      )

      # network.resource_group_name may return the default resource group name in global configurations. See network.rb.
      default_resource_group_name = @azure_config.resource_group_name
      if network_security_group.nil? && resource_group_name != default_resource_group_name
        @logger.info("Cannot find the network security group '#{network_security_group_cfg.name}' in the resource group '#{resource_group_name}', trying to search it in the default resource group '#{default_resource_group_name}'")
        network_security_group = @azure_client.get_network_security_group_by_name(default_resource_group_name, network_security_group_cfg.name)
      end

      cloud_error("Cannot find the network security group '#{network_security_group_cfg.name}'") if network_security_group.nil?
      network_security_group
    end

    def _get_application_security_groups(vm_props, network)
      application_security_groups = []
      # Application security group name can be specified in vm_types or vm_extensions and networks (ordered by priority)
      application_security_group_names = vm_props.application_security_groups.nil? ? network.application_security_groups : vm_props.application_security_groups
      application_security_group_names.each do |application_security_group_name|
        # The resource group which the ASG belongs to can be specified in networks and global configuration (ordered by priority)
        resource_group_name = network.resource_group_name
        application_security_group = @azure_client.get_application_security_group_by_name(resource_group_name, application_security_group_name)
        # network.resource_group_name may return the default resource group name in global configurations. See network.rb.
        default_resource_group_name = @azure_config.resource_group_name
        if application_security_group.nil? && resource_group_name != default_resource_group_name
          @logger.info("Cannot find the application security group '#{application_security_group_name}' in the resource group '#{resource_group_name}', trying to search it in the default resource group '#{default_resource_group_name}'")
          application_security_group = @azure_client.get_application_security_group_by_name(default_resource_group_name, application_security_group_name)
        end
        cloud_error("Cannot find the application security group '#{application_security_group_name}'") if application_security_group.nil?
        application_security_groups.push(application_security_group)
      end
      application_security_groups
    end

    def _get_ip_forwarding(vm_props, network)
      # ip_forwarding can be specified in vm_types or vm_extensions and networks (ordered by priority)
      ip_forwarding = vm_props.ip_forwarding.nil? ? network.ip_forwarding : vm_props.ip_forwarding
      ip_forwarding
    end

    def _get_accelerated_networking(vm_props, network)
      # accelerated_networking can be specified in vm_types or vm_extensions and networks (ordered by priority)
      accelerated_networking = vm_props.accelerated_networking.nil? ? network.accelerated_networking : vm_props.accelerated_networking
      accelerated_networking
    end

    def _get_public_ip(vip_network)
      public_ip = nil
      unless vip_network.nil?
        resource_group_name = vip_network.resource_group_name
        public_ip = @azure_client.list_public_ips(resource_group_name).find { |ip| ip[:ip_address] == vip_network.public_ip }
        cloud_error("Cannot find the public IP address '#{vip_network.public_ip}' in the resource group '#{resource_group_name}'") if public_ip.nil?
      end
      public_ip
    end

    # @return [Array<Hash>]
    # @see Bosh::AzureCloud::AzureClient.create_network_interface
    def _get_load_balancers(vm_props)
      load_balancers = nil
      load_balancer_configs = vm_props.load_balancers
      unless load_balancer_configs.nil?
        load_balancers = load_balancer_configs.map do |load_balancer_config|
          load_balancer = @azure_client.get_load_balancer_by_name(load_balancer_config.resource_group_name, load_balancer_config.name)
          cloud_error("Cannot find the load balancer '#{load_balancer_config.name}'") if load_balancer.nil?
          load_balancer
        end
      end
      load_balancers
    end

    # @return [Array<Hash>]
    # @see Bosh::AzureCloud::AzureClient.create_network_interface
    def _get_application_gateways(vm_props)
      application_gateways = nil
      application_gateway_configs = vm_props.application_gateways
      unless application_gateway_configs.nil?
        # NOTE: The following block gets the Azure API info for each Bosh AGW config (from the vm_type config).
        application_gateways = application_gateway_configs.map do |application_gateway_config|
          application_gateway = @azure_client.get_application_gateway_by_name(application_gateway_config.resource_group_name, application_gateway_config.name)
          cloud_error("Cannot find the application gateway '#{application_gateway_config.name}'") if application_gateway.nil?

          if application_gateway_config.backend_pool_name
            # NOTE: This is the only place where we simultaneously have both the Bosh AGW config (from the vm_type) AND the Azure AGW info (from the Azure API).
            # Since the `AzureClient.create_network_interface` method only uses the first backend pool,
            # and since there is not a 1-to-1 mapping between the vm_type AGW configs and AGWs (despite the config property name, each vm_type AGW config actually represents a single AGW Backend Pool, not a whole AGW),
            # we can therefore remove all pools EXCEPT the specified pool.
            # To handle multiple pools of a single AGW, you should use 1 vm_type AGW Hash (with AGW name + backend_pool_name) per pool.
            pools = application_gateway[:backend_address_pools]
            pools = [pools] unless pools.is_a?(Array)
            pool = pools.find { |p| Hash(p)[:name] == application_gateway_config.backend_pool_name }
            cloud_error("'#{application_gateway_config.name}' does not have a backend_pool named '#{application_gateway_config.backend_pool_name}': #{application_gateway}") if pool.nil?

            application_gateway[:backend_address_pools] = [pool]
          end
          application_gateway
        end
      end
      application_gateways
    end

    def _get_or_create_public_ip(resource_group_name, vm_name, location, vm_props, network_configurator)
      public_ip = _get_public_ip(network_configurator.vip_network)
      if public_ip.nil? && vm_props.assign_dynamic_public_ip == true
        # create dynamic public ip
        idle_timeout_in_minutes = @azure_config.pip_idle_timeout_in_minutes
        validate_idle_timeout(idle_timeout_in_minutes)
        public_ip_params = {
          name: vm_name,
          location: location,
          is_static: false,
          idle_timeout_in_minutes: idle_timeout_in_minutes
        }
        public_ip_params[:zone] = vm_props.availability_zone.to_s unless vm_props.availability_zone.nil?
        @azure_client.create_public_ip(resource_group_name, public_ip_params)
        public_ip = @azure_client.get_public_ip_by_name(resource_group_name, vm_name)
      end
      public_ip
    end

    # @return [Array<Hash>] one Hash (returned by Bosh::AzureCloud::AzureClient.get_network_interface_by_name)  per network interface created
    def _create_network_interfaces(resource_group_name, vm_name, location, vm_props, network_configurator, primary_nic_tags = AZURE_TAGS)
      # Tasks to prepare before creating NICs:
      #   * prepare public ip
      #   * prepare load balancer(s)
      #   * prepare application gateway(s)
      tasks_preparing = []

      tasks_preparing.push(
        task_get_or_create_public_ip = Concurrent::Future.execute do
          _get_or_create_public_ip(resource_group_name, vm_name, location, vm_props, network_configurator)
        end
      )
      tasks_preparing.push(
        task_get_load_balancers = Concurrent::Future.execute do
          _get_load_balancers(vm_props)
        end
      )
      tasks_preparing.push(
        task_get_application_gateways = Concurrent::Future.execute do
          _get_application_gateways(vm_props)
        end
      )

      # Calling .wait before .value! to make sure that all tasks are completed.
      tasks_preparing.map(&:wait)

      public_ip = task_get_or_create_public_ip.value!
      load_balancers = task_get_load_balancers.value!
      application_gateways = task_get_application_gateways.value!

      # tasks to create NICs, NICs will be created in different threads
      tasks_creating = []

      networks = network_configurator.networks
      networks.each_with_index do |network, index|
        network_security_group = _get_network_security_group(vm_props, network)
        application_security_groups = _get_application_security_groups(vm_props, network)
        ip_forwarding = _get_ip_forwarding(vm_props, network)
        accelerated_networking = _get_accelerated_networking(vm_props, network)
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
        nic_params[:subnet] = _get_network_subnet(network)
        # NOTE: The first NIC is the Primary/Gateway network. See: `Bosh::AzureCloud::NetworkConfigurator.initialize`.
        if index.zero?
          nic_params[:public_ip] = public_ip
          nic_params[:tags] = primary_nic_tags
          nic_params[:load_balancers] = load_balancers
          nic_params[:application_gateways] = application_gateways
        else
          nic_params[:public_ip] = nil
          nic_params[:tags] = AZURE_TAGS
          nic_params[:load_balancers] = nil
          nic_params[:application_gateways] = nil
        end
        tasks_creating.push(
          Concurrent::Future.execute do
            @azure_client.create_network_interface(resource_group_name, nic_params)
            @azure_client.get_network_interface_by_name(resource_group_name, nic_name)
          end
        )
      end
      # Calling .wait before .value! to make sure that all tasks are completed.
      tasks_creating.map(&:wait)
      tasks_creating.map(&:value!)
    end

    def _delete_possible_network_interfaces(resource_group_name, vm_name)
      network_interfaces = @azure_client.list_network_interfaces_by_keyword(resource_group_name, vm_name)
      tasks = []
      network_interfaces.each do |network_interface|
        tasks.push(
          Concurrent::Future.execute do
            @azure_client.delete_network_interface(resource_group_name, network_interface[:name])
          end
        )
      end
      # Calling .wait before .wait! to make sure that all tasks are completed.
      tasks.map(&:wait)
      tasks.map(&:wait!)
    end
  end
end
