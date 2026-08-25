# frozen_string_literal: true

require 'ipaddr'

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
      vm_props.ip_forwarding.nil? ? network.ip_forwarding : vm_props.ip_forwarding
    end

    def _get_accelerated_networking(vm_props, network)
      # accelerated_networking can be specified in vm_types or vm_extensions and networks (ordered by priority)
      vm_props.accelerated_networking.nil? ? network.accelerated_networking : vm_props.accelerated_networking
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
        # NOTE: The following block gets the Azure API info for each Bosh AGW config (from the vm_type config).
        load_balancers = load_balancer_configs.map do |load_balancer_config|
          load_balancer = @azure_client.get_load_balancer_by_name(load_balancer_config.resource_group_name, load_balancer_config.name)

          cloud_error("Cannot find the load balancer '#{load_balancer_config.name}'") if load_balancer.nil?

          pools = load_balancer[:backend_address_pools]
          pools = [pools] unless pools.is_a?(Array)

          # NOTE: The following block sets the type of each backend pool in the load balancer, which is used to filter out backend pools that are not associated with NICs when creating network interfaces.
          _detect_backend_pool_type(load_balancer_config, pools)

          load_balancer[:resource_group_name] = vm_props.resource_group_name
          unless load_balancer_config.resource_group_name.nil?
            load_balancer[:resource_group_name] = load_balancer_config.resource_group_name
          end

          if load_balancer_config.backend_pool_name
            # NOTE: This is the only place where we simultaneously have both the Bosh LB config (from the vm_type) AND the Azure LB info (from the Azure API).
            # Since the `AzureClient.create_network_interface` method only uses the first backend pool,
            # and since there is not a 1-to-1 mapping between the vm_type LB configs and LBs (despite the config property name, each vm_type LB config actually represents a single LB Backend Pool, not a whole LB),
            # we can therefore remove all pools EXCEPT the specified pool.
            # To handle multiple pools of a single LB, you should use 1 vm_type LB Hash (with LB name + backend_pool_name) per pool.
            pool = pools.find { |p| Hash(p)[:name].casecmp?(load_balancer_config.backend_pool_name) }
            cloud_error("'#{load_balancer_config.name}' does not have a backend_pool named '#{load_balancer_config.backend_pool_name}': #{load_balancer}") if pool.nil?

            load_balancer[:backend_address_pools] = [pool]
          end

          if load_balancer_config.backend_pool_name_v6
            pool_v6 = pools.find { |p| Hash(p)[:name].casecmp?(load_balancer_config.backend_pool_name_v6) }
            cloud_error("'#{load_balancer_config.name}' does not have a backend_pool named '#{load_balancer_config.backend_pool_name_v6}': #{load_balancer}") if pool_v6.nil?

            load_balancer[:backend_address_pools_v6] = [pool_v6]
          end

          load_balancer
        end
      end
      load_balancers
    end

    # Detect the type of each backend pool in the load balancer, which is used to filter out backend pools that are not associated with NICs when creating network interfaces.
    #
    # @param [LoadBalancerConfig] load_balancer_config load balancer config
    # @param [Array<Hash>] pools backend pools in the load balancer
    # @return [Array<Hash>]
    def _detect_backend_pool_type(load_balancer_config, pools)
      default_backend_pool_type = load_balancer_config.default_backend_pool_type

      pools.each do |pool|
        pool[:backend_address_pools_type] = default_backend_pool_type

        has_nic_members = Array(pool[:backend_ip_configurations]).any?
        has_ip_members  = Array(pool[:load_balancer_backend_addresses]).any?

        # NIC membership wins only when NICs are actually attached.
        pool[:backend_address_pools_type] = LOAD_BALANCER_BACKEND_POOL_TYPE_NIC if has_nic_members
        pool[:backend_address_pools_type] = LOAD_BALANCER_BACKEND_POOL_TYPE_IP if has_ip_members && !has_nic_members

      end
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
      public_ip_nic_index = _get_public_ip_nic_index(network_configurator)

      # tasks to create NICs, NICs will be created in different threads
      tasks_creating = []

      nic_groups = network_configurator.nic_groups
      nic_groups.each_with_index do |group_networks, nic_index|
        primary_network = group_networks.first

        network_security_group = _get_network_security_group(vm_props, primary_network)
        application_security_groups = _get_application_security_groups(vm_props, primary_network)
        ip_forwarding = _get_ip_forwarding(vm_props, primary_network)
        accelerated_networking = _get_accelerated_networking(vm_props, primary_network)
        nic_name = "#{vm_name}-#{nic_index}"
        subnet = _get_network_subnet(primary_network)

        networks_with_ip_versions = group_networks.map do |network|
          [network, _detect_ip_version(network)]
        end
        ipv4_networks, ipv6_networks = networks_with_ip_versions.partition do |_network, ip_version|
          ip_version == 'IPv4'
        end
        networks_with_ip_versions = ipv4_networks + ipv6_networks

        ip_configurations = networks_with_ip_versions.each_with_index.map do |(network, ip_version), ipconfig_index|
          ipconfig = {
            name: "ipconfig#{nic_index}-#{ipconfig_index}",
            ip_version: ip_version,
            subnet: subnet
          }
          ipconfig[:private_ip] = network.private_ip if network.respond_to?(:private_ip)
          ipconfig
        end

        nic_params = {
          name: nic_name,
          location: location,
          network_security_group: network_security_group,
          application_security_groups: application_security_groups,
          enable_ip_forwarding: ip_forwarding,
          enable_accelerated_networking: accelerated_networking,
          ip_configurations: ip_configurations
        }
        nic_params[:public_ip] = nic_index == public_ip_nic_index ? public_ip : nil

        # NOTE: The first NIC is the Primary/Gateway network. See: `Bosh::AzureCloud::NetworkConfigurator.initialize`.
        if nic_index.zero?
          nic_params[:tags] = primary_nic_tags
          nic_params[:load_balancers] = load_balancers
          nic_params[:application_gateways] = application_gateways
        else
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

    def _get_public_ip_nic_index(network_configurator)
      vip_network = network_configurator.vip_network
      vip_nic_group = vip_network&.spec&.[]('nic_group')
      return 0 if vip_nic_group.nil?

      nic_index = network_configurator.nic_groups.index do |group_networks|
        group_networks.first.nic_group == vip_nic_group
      end
      cloud_error("Cannot find nic_group '#{vip_nic_group}' referenced by the vip network") if nic_index.nil?

      nic_index
    end

    # Determine whether a network's IP is IPv4 or IPv6
    def _detect_ip_version(network)
      has_explicit_ip = network.respond_to?(:private_ip) && network.private_ip && !network.private_ip.empty?
      return 'IPv4' unless has_explicit_ip

      IPAddr.new(network.private_ip).ipv6? ? 'IPv6' : 'IPv4'
    rescue IPAddr::InvalidAddressError => e
      @logger.warn("Invalid IP address '#{network.private_ip}': #{e.message}, defaulting to IPv4")
      'IPv4'
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

    # @param [String] private_ip - The private IP address of the VM to be
    # @param [String] vnet_id - The virtual network ID of the VM to be added to the backend pool.
    # @param [String] backend_address_name - The name of the backend address to be added to the backend pool.
    # @return [Hash] - The backend address to be added to the backend pool.
    def _build_backend_address(properties = {}, backend_address_name = "", private_ip = nil, vnet_id = nil)
      backend_address = {}
      if backend_address_name.empty?
        # Azure generates a random uuid when adding a VM manually via ui to the backend pool.
        backend_address_name = SecureRandom.uuid
      end

      backend_address[:name] = "#{backend_address_name}"
      backend_address[:properties] = properties

      unless private_ip.nil? && vnet_id.nil?
        backend_address[:properties][:ipAddress] = private_ip
        backend_address[:properties][:virtualNetwork] = {}
        backend_address[:properties][:virtualNetwork][:id] = vnet_id
      end

      backend_address
    end

    # @param [Hash] load_balancer - returned by Bosh::AzureCloud::AzureClient.get_load_balancer_by_name
    # @param [Array<Hash>] vm_network_interfaces - returned by Bosh::AzureCloud::AzureClient.create_virtual_machine
    # @return [Array<Hash>] - The backend addresses to
    def _calculate_backend_addresses_for_load_balancer(load_balancer, vm_network_interfaces)
      backend_addresses = []
      primary_nic = vm_network_interfaces.find { |nic| nic[:primary] }

      return backend_addresses if primary_nic.nil?

      load_balancer[:backend_address_pools].each do |pool|
        pool_type = pool[:backend_address_pools_type]
        next unless pool_type == LOAD_BALANCER_BACKEND_POOL_TYPE_IP

        backend_addresses_v4_pool = {}
        backend_addresses_v4_pool[:name] = pool[:name]
        backend_addresses_v4_pool[:loadBalancerBackendAddresses] = []

        # Ipv4 adresse und subnet
        ip = primary_nic[:ip_configurations].find { |ip_config| ip_config[:private_ip] && !ip_config[:private_ip].empty? && ip_config[:private_ip_address_version].to_s.upcase == 'IPV4' }

        unless ip.nil?
          private_ip = ip[:private_ip]
          subnet_id = ip[:subnet][:id]
          vnet_id = subnet_id.split('/subnets/')[0]

          backend_addresses_v4_pool[:loadBalancerBackendAddresses] << _build_backend_address({}, "", private_ip, vnet_id)
        end

        backend_addresses << backend_addresses_v4_pool unless backend_addresses_v4_pool[:loadBalancerBackendAddresses].empty?
      end

      unless load_balancer[:backend_address_pools_v6].nil? || load_balancer[:backend_address_pools_v6].empty?
        load_balancer[:backend_address_pools_v6].each do |pool_v6|
          pool_type_v6 = pool_v6[:backend_address_pools_type]
          next unless pool_type_v6 == LOAD_BALANCER_BACKEND_POOL_TYPE_IP

          backend_addresses_v6_pool = {}
          backend_addresses_v6_pool[:name] = pool_v6[:name]
          backend_addresses_v6_pool[:loadBalancerBackendAddresses] = []

          # Ipv6 adresse und subnet
          ip = primary_nic[:ip_configurations].find { |ip_config| ip_config[:private_ip] && !ip_config[:private_ip].empty? && ip_config[:private_ip_address_version].to_s.upcase == 'IPV6' }

          unless ip.nil?
            private_ip = ip[:private_ip]
            subnet_id = ip[:subnet][:id]
            vnet_id = subnet_id.split('/subnets/')[0]

            backend_addresses_v6_pool[:loadBalancerBackendAddresses] << _build_backend_address({}, "", private_ip, vnet_id)
          end
          backend_addresses << backend_addresses_v6_pool unless backend_addresses_v6_pool[:loadBalancerBackendAddresses].empty?
        end
      end
      backend_addresses
    end

    # @param [Hash] virtual_machine_result - returned by Bosh::AzureCloud::AzureClient.get_virtual_machine_by_name
    # @return [void]
    def _remove_vm_from_load_balancer_backend_pool(virtual_machine_result)
      return if virtual_machine_result.nil?

      # Collect all the private IP addresses of the VM from its network interfaces that are not associated with a load balancer backend pool.
      vm_ips = virtual_machine_result[:network_interfaces].flat_map { |nic|
        nic[:ip_configurations]
          .reject { |ip_config| Array(ip_config[:load_balancers]).any? }
          .map { |ip_config| ip_config[:private_ip] }
          .compact
      }

      # If there is not load balancer ip based backend pool, then the backend pool is nic based and managed by azure. In this case, we don't need to remove the vm from the backend pool.
      if vm_ips.empty?
        @logger.info("The VM '#{virtual_machine_result[:name]}' has no private IP addresses that are not associated with a load balancer backend pool, so the pool is nic based and managed by azure.")
        return
      end

      # Collect the virtual network IDs of the VM from its network interfaces.
      vm_vnet = virtual_machine_result[:network_interfaces].flat_map { |nic|
        nic[:ip_configurations].map { |ip_config| ip_config[:subnet][:id].split('/subnets/')[0] }.compact
      }
      vm_vnet.uniq!

      # Load all load balancers
      # Lock the operation until the load balancer backend pool is updated to avoid race conditions.
      flock("#{CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX) do

        load_balancers = @azure_client.list_all_load_balancers()
        return if load_balancers.nil? || load_balancers.empty?

        #Find load balancer backend pool that has the ip addresses of the vm assigned.
        load_balancer_tu = load_balancers.find_all { |load_balancer|
          Array(load_balancer[:backend_address_pools]).any? {
            |pool| Array(pool[:load_balancer_backend_addresses]).any? {
              |backend_address| (vm_ips.include?(backend_address['properties']['ipAddress']) && vm_vnet.include?(backend_address['properties']['virtualNetwork']['id'])) } }
        }

        unless load_balancer_tu.nil? || load_balancer_tu.empty?
          load_balancer_tu.each do |load_balancer|
              resource_group = load_balancer[:id].split('/resourceGroups/')[1].split('/')[0]

              load_balancer[:backend_address_pools].each do |pool|
                existing_addresses = Array(pool[:load_balancer_backend_addresses])
                next if existing_addresses.empty?

                matches_vm = existing_addresses.any? do |backend_address|
                  vm_ips.include?(backend_address['properties']['ipAddress']) &&
                    vm_vnet.include?(backend_address['properties']['virtualNetwork']['id'])
                end
                next unless matches_vm

                backend_addresses_pool = {}
                backend_addresses_pool[:name] = pool[:name]
                backend_addresses_pool[:loadBalancerBackendAddresses] = []

                Array(pool[:load_balancer_backend_addresses]).each do |backend_address|
                  unless vm_ips.include?(backend_address['properties']['ipAddress']) && vm_vnet.include?(backend_address['properties']['virtualNetwork']['id'])
                    poolVmName = backend_address['name']
                    backend_addresses_pool[:loadBalancerBackendAddresses] << _build_backend_address(backend_address['properties'], poolVmName)
                  end
                end

                @azure_client.update_load_balancer_backend_pool(resource_group, load_balancer[:name], pool[:name], backend_addresses_pool[:loadBalancerBackendAddresses])

            end
          end
        end
      end
    end

    # @param [Array<Hash>] load_balancers - one Hash (returned by Bosh::AzureCloud::AzureClient.get_load_balancer_by_name) per load balancer
    # @param [Hash] virtual_machine_result - returned by Bosh::AzureCloud::AzureClient.create_virtual_machine
    # @return [void]
    def _add_vm_to_load_balancer_backend_pool(load_balancers, virtual_machine_result)
      return if virtual_machine_result.nil? || load_balancers.nil? || load_balancers.empty?

      vm_network_interfaces = virtual_machine_result[:network_interfaces]

      load_balancers.each do |load_balancer|
        load_balancer_name = load_balancer[:name]
        resource_group_name = load_balancer[:resource_group_name]

        # First build the new backend addresses for the load balancer, then update the load balancer with the new backend addresses.
        backend_addresses = _calculate_backend_addresses_for_load_balancer(load_balancer, vm_network_interfaces)

        # First get the current backend pool of the load balancer, then update the backend pool with the new backend addresses.
        flock("#{CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX) do
          load_balancer_current = @azure_client.get_load_balancer_by_name(resource_group_name, load_balancer_name)
          next if load_balancer_current.nil?

          load_balancer_current[:backend_address_pools].each do |pool|
            pool_name = pool[:name]
            backend_addresses_pool = backend_addresses.find { |p| p[:name].casecmp?(pool_name) }
            unless backend_addresses_pool.nil?
               new_ips = backend_addresses_pool[:loadBalancerBackendAddresses].map { |a| a[:properties][:ipAddress] }
               Array(pool[:load_balancer_backend_addresses]).each do |backend_address|
                 next if new_ips.include?(backend_address['properties']['ipAddress'])

                 backend_addresses_pool[:loadBalancerBackendAddresses] << _build_backend_address(backend_address['properties'], backend_address['name'])
               end

              @azure_client.update_load_balancer_backend_pool(resource_group_name, load_balancer_name, pool_name, backend_addresses_pool[:loadBalancerBackendAddresses]) unless backend_addresses_pool[:loadBalancerBackendAddresses].empty?

            end
          end
        end
      end
    end
  end
end
