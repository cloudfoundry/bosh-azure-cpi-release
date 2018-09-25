# frozen_string_literal: true

module Bosh::AzureCloud
  class VMManager < VMManagerBase
    private

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

    def _get_load_balancer(vm_props)
      load_balancer = nil
      unless vm_props.load_balancer.nil?
        load_balancer_name = vm_props.load_balancer
        load_balancer = @azure_client.get_load_balancer_by_name(load_balancer_name)
        cloud_error("Cannot find the load balancer '#{load_balancer_name}'") if load_balancer.nil?
      end
      load_balancer
    end

    def _get_application_gateway(vm_props)
      application_gateway = nil
      unless vm_props.application_gateway.nil?
        application_gateway_name = vm_props.application_gateway
        application_gateway = @azure_client.get_application_gateway_by_name(application_gateway_name)
        cloud_error("Cannot find the application gateway '#{application_gateway_name}'") if application_gateway.nil?
      end
      application_gateway
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

    def _create_network_interfaces(resource_group_name, vm_name, location, vm_props, network_configurator, primary_nic_tags = AZURE_TAGS)
      # Tasks to prepare before creating NICs:
      #   * preapre public ip
      #   * prepare load balancer
      #   * prepare application gateway
      tasks_preparing = []

      tasks_preparing.push(
        task_get_or_create_public_ip = Concurrent::Future.execute do
          _get_or_create_public_ip(resource_group_name, vm_name, location, vm_props, network_configurator)
        end
      )
      tasks_preparing.push(
        task_get_load_balancer = Concurrent::Future.execute do
          _get_load_balancer(vm_props)
        end
      )
      tasks_preparing.push(
        task_get_application_gateway = Concurrent::Future.execute do
          _get_application_gateway(vm_props)
        end
      )

      # Calling .wait before .value! to make sure that all tasks are completed.
      tasks_preparing.map(&:wait)

      public_ip = task_get_or_create_public_ip.value!
      load_balancer = task_get_load_balancer.value!
      application_gateway = task_get_application_gateway.value!

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
