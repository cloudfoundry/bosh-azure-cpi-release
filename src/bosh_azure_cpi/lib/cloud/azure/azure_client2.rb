###############################################################################
# This client is for using Azure Resource Manager. It will be obsoleted soon
# after azure-sdk-for-ruby supports Azure Resource Manager.
###############################################################################
module Bosh::AzureCloud
  class AzureError < Bosh::Clouds::CloudError; end
  class AzureUnauthorizedError < AzureError; end
  class AzureNoFoundError < AzureError; end
  class AzureConflictError < AzureError; end
  class AzureInternalError < AzureError; end
  class AzureAsynInternalError < AzureError; end

  class AzureClient2
    include Helpers

    USER_AGENT     = 'BOSH-AZURE-CPI'

    HTTP_CODE_OK                  = 200
    HTTP_CODE_CREATED             = 201
    HTTP_CODE_ACCEPTED            = 202
    HTTP_CODE_NOCONTENT           = 204
    HTTP_CODE_PARTIALCONTENT      = 206
    HTTP_CODE_BADREQUEST          = 400
    HTTP_CODE_UNAUTHORIZED        = 401
    HTTP_CODE_FORBIDDEN           = 403
    HTTP_CODE_NOTFOUND            = 404
    HTTP_CODE_CONFLICT            = 409
    HTTP_CODE_LENGTHREQUIRED      = 411
    HTTP_CODE_PRECONDITIONFAILED  = 412
    HTTP_CODE_INTERNALSERVERERROR = 500

    # https://azure.microsoft.com/en-us/documentation/articles/best-practices-retry-service-specific/#more-information-6
    AZURE_RETRY_ERROR_CODES       = [408, 500, 502, 503, 504]

    REST_API_PROVIDER_COMPUTER           = 'Microsoft.Compute'
    REST_API_COMPUTER_VIRTUAL_MACHINES   = 'virtualMachines'
    REST_API_COMPUTER_AVAILABILITY_SETS  = 'availabilitySets'

    REST_API_PROVIDER_NETWORK            = 'Microsoft.Network'
    REST_API_NETWORK_PUBLIC_IP_ADDRESSES = 'publicIPAddresses'
    REST_API_NETWORK_LOAD_BALANCERS      = 'loadBalancers'
    REST_API_NETWORK_INTERFACES          = 'networkInterfaces'
    REST_API_NETWORK_VNETS               = 'virtualNetworks'
    REST_API_NETWORK_SECURITY_GROUPS     = 'networkSecurityGroups'

    REST_API_PROVIDER_STORAGE            = 'Microsoft.Storage'
    REST_API_STORAGE_ACCOUNTS            = 'storageAccounts'

    def initialize(azure_properties, logger)
      @logger = logger

      @azure_properties = azure_properties
    end

    # Common
    def rest_api_url(resource_provider, resource_type, name = nil, others = nil)
      url =  "/subscriptions/#{URI.escape(@azure_properties['subscription_id'])}"
      url += "/resourceGroups/#{URI.escape(@azure_properties['resource_group_name'])}"
      url += "/providers/#{resource_provider}"
      url += "/#{resource_type}"
      url += "/#{URI.escape(name)}" unless name.nil?
      url += "/#{URI.escape(others)}" unless others.nil?
      url
    end

    def parse_name_from_id(id)
      ret = id.match('/subscriptions/([^/]*)/resourceGroups/([^/]*)/providers/([^/]*)/([^/]*)/([^/]*)(.*)')
      raise AzureError, "\"#{id}\" is not a valid URL." if ret.nil?
      result = {}
      result[:subscription_id]     = ret[1]
      result[:resource_group_name] = ret[2]
      result[:provider_name]       = ret[3]
      result[:resource_type]       = ret[4]
      result[:resource_name]       = ret[5]
      result
    end

    def get_resource_by_id(url, params = {})
      result = nil
      begin
        result = http_get(url, params)
      rescue AzureNoFoundError => e
        result = nil
      end
      result
    end

    # Resource Groups
    def get_resource_group()
      resource_group = nil

      url =  "/subscriptions/#{URI.escape(@azure_properties['subscription_id'])}"
      url += "/resourceGroups/#{URI.escape(@azure_properties['resource_group_name'])}"
      result = get_resource_by_id(url)

      unless result.nil?
        resource_group = {}
        resource_group[:id]                 = result['id']
        resource_group[:name]               = result['name']
        resource_group[:location]           = result['location']
        resource_group[:tags]               = result['tags']
        resource_group[:provisioning_state] = result['properties']['provisioningState']
      end
      resource_group
    end

    # Compute/Virtual Machines
    # Public: Provisions a virtual machine based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [Hash] vm_params         - Parameters for creating the virtual machine.
    # @param [Hash] network_interface - Network Interface Instance.
    # @param [Hash] availability_set  - Availability set.
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+                 - String. Name of virtual machine.
    # * +:location+             - String. The location where the virtual machine will be created.
    # * +:tags+                 - Hash. Tags of virtual machine.
    # * +:vm_size+              - String. Specifies the size of the virtual machine instance.
    # * +:username+             - String. User name for the virtual machine instance.
    # * +:custom_data+          - String. Specifies a base-64 encoded string of custom data. 
    # * +:image_uri+            - String. The URI of the image.
    # * +:os_disk_name+         - String. The name of the OS disk for the virtual machine instance.
    # * +:os_vhd_uri+           - String. The URI of the OS disk for the virtual machine instance.
    # * +:ephemeral_disk_name+  - String. The name of the ephemeral disk for the virtual machine instance.
    # * +:ephemeral_disk_uri+   - String. The URI of the ephemeral disk for the virtual machine instance.
    # * +:ephemeral_disk_size+  - Integer. The size in GiB of the ephemeral disk for the virtual machine instance.
    # * #:caching+              - String. The caching option of the OS disk. Caching option: None, ReadOnly or ReadWrite
    # * +:ssh_cert_data+        - String. The content of SSH certificate.
    #
    def create_virtual_machine(vm_params, network_interface, availability_set = nil)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, vm_params[:name])
      vm = {
        'name'       => vm_params[:name],
        'location'   => vm_params[:location],
        'type'       => "#{REST_API_PROVIDER_COMPUTER}/#{REST_API_COMPUTER_VIRTUAL_MACHINES}",
        'tags'       => vm_params[:metadata],
        'properties' => {
          'hardwareProfile' => {
            'vmSize' => vm_params[:vm_size]
          },
          'osProfile' => {
            'customData'         => vm_params[:custom_data],
            'computername'       => vm_params[:name],
            'adminUsername'      => vm_params[:username],
            'linuxConfiguration' => {
              'disablePasswordAuthentication' => 'true',
              'ssh' => {
                'publicKeys' => [
                  {
                    'path'    => "/home/#{vm_params[:username]}/.ssh/authorized_keys",
                    'keyData' => vm_params[:ssh_cert_data],
                  }
                ]
              },
            },
          },
          'storageProfile' => {
            'osDisk' => {
              'name'         => vm_params[:os_disk_name],
              'osType'       => 'Linux',
              'createOption' => 'FromImage',
              'caching'      => vm_params[:caching],
              'image'        => {
                'uri' => vm_params[:image_uri]
              },
              'vhd'          => {
                'uri' => vm_params[:os_vhd_uri]
              }
            },
            'dataDisks' => [{
                'name'         => vm_params[:ephemeral_disk_name],
                'lun'          => 0,
                'createOption' => 'Empty',
                'diskSizeGB'   => vm_params[:ephemeral_disk_size],
                'caching'      => 'ReadWrite',
                'vhd'          => {
                  'uri' => vm_params[:ephemeral_disk_uri]
                }
              }]
          },
          'networkProfile' => {
            'networkInterfaces' => [
              {
                'id' => network_interface[:id]
              }
            ]
          }
        }
      }

      unless availability_set.nil?
        vm['properties']['availabilitySet'] = {
          'id' => availability_set[:id]
        }
      end

      params = {
        'validating' => 'true'
      }

      http_put(url, vm, params)
    end

    def restart_virtual_machine(name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name, 'restart')
      http_post(url)
    end

    # Public: Set tags for a VM
    # @param [String] name Name of virtual machine.
    # @param [Hash] metadata metadata key/value pairs.
    def update_tags_of_virtual_machine(name, tags)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      vm = get_resource_by_id(url)
      if vm.nil?
        raise AzureNoFoundError, "update_tags_of_virtual_machine - cannot find the virtual machine by name \"#{name}\""
      end

      vm['tags'] = tags
      http_put(url, vm)
    end

    # Attach a specified disk to a VM
    # @param [String] name Name of virtual machine.
    # @param [String] disk_name Disk name.
    # @param [String] disk_uri URI of disk
    # @param [String] caching Caching option: None, ReadOnly or ReadWrite
    def attach_disk_to_virtual_machine(name, disk_name, disk_uri, caching)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      vm = get_resource_by_id(url)
      if vm.nil?
        raise AzureNoFoundError, "attach_disk_to_virtual_machine - cannot find the virtual machine by name `#{name}'"
      end

      # 0 is always used by the ephemeral disk. Search an available lun from 1.
      # Max data disks on Azure is 64.
      lun = 0
      data_disks = vm['properties']['storageProfile']['dataDisks']
      for i in 1..63
        disk = data_disks.find { |disk| disk['lun'] == i}
        if disk.nil?
          lun = i
          break
        end
      end

      if lun == 0
        raise AzureError, "attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine `#{name}' for the new disk `#{disk_name}'"
      end

      new_disk = {
        'name'         => disk_name,
        'lun'          => lun,
        'createOption' => 'Attach',
        'caching'      => caching,
        'vhd'          => { 'uri' => disk_uri }
      }
      vm['properties']['storageProfile']['dataDisks'].push(new_disk)
      @logger.info("attach_disk_to_virtual_machine - attach disk `#{disk_name}' to `#{lun}'")
      http_put(url, vm)
      disk = {
        :name         => disk_name,
        :lun          => lun,
        :createOption => 'Attach',
        :caching      => caching,
        :vhd          => { :uri => disk_uri }
      }
    end

    def detach_disk_from_virtual_machine(name, disk_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      vm = get_resource_by_id(url)
      if vm.nil?
        raise AzureNoFoundError, "detach_disk_from_virtual_machine - cannot find the virtual machine by name \"#{name}\""
      end

      @logger.debug("detach_disk_from_virtual_machine - virtual machine:\n#{JSON.pretty_generate(vm)}")
      disk = vm['properties']['storageProfile']['dataDisks'].find { |disk| disk['name'] == disk_name}
      raise Bosh::Clouds::DiskNotAttached.new(true),
        "The disk #{disk_name} is not attached to the virtual machine #{name}" if disk.nil?

      vm['properties']['storageProfile']['dataDisks'].delete_if { |disk| disk['name'] == disk_name}

      @logger.info("detach_disk_from_virtual_machine - detach disk #{disk_name} from lun #{disk['lun']}")
      http_put(url, vm)
    end

    def get_virtual_machine_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      get_virtual_machine(url)
    end

    def get_virtual_machine(url)
      vm = nil
      result = get_resource_by_id(url)

      unless result.nil?
        vm = {}
        vm[:id]       = result['id']
        vm[:name]     = result['name']
        vm[:location] = result['location']
        vm[:tags]     = result['tags']

        properties = result['properties']
        vm[:provisioning_state] = properties['provisioningState']
        vm[:size]               = properties['hardwareProfile']['vmSize']

        unless properties['availabilitySet'].nil?
          vm[:availability_set] = get_availability_set(properties['availabilitySet']['id'])
        end

        storageProfile = properties['storageProfile']
        vm[:os_disk] = {}
        vm[:os_disk][:name]    = storageProfile['osDisk']['name']
        vm[:os_disk][:uri]     = storageProfile['osDisk']['vhd']['uri']
        vm[:os_disk][:caching] = storageProfile['osDisk']['caching']

        vm[:data_disks] = []
        storageProfile['dataDisks'].each do |data_disk|
          disk = {}
          disk[:name]    = data_disk['name']
          disk[:lun]     = data_disk['lun']
          disk[:uri]     = data_disk['vhd']['uri']
          disk[:caching] = data_disk['caching']
          vm[:data_disks].push(disk)
        end

        interface_id = properties['networkProfile']['networkInterfaces'][0]['id']
        vm[:network_interface] = get_network_interface(interface_id)
      end
      vm
    end

    def delete_virtual_machine(name)
      @logger.debug("delete_virtual_machine - trying to delete #{name}")
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      http_delete(url)
    end

    # Compute/Availability Sets
    # Public: Create an availability set based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [Hash] avset_params        - Parameters for creating the availability set.
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+                         - String. Name of availability set.
    # * +:location+                     - String. The location where the availability set will be created.
    # * +:tags+                         - Hash. Tags of availability set.
    # * +:platform_update_domain_count+ - Integer. Specifies the update domain count of availability set.
    # * +:platform_fault_domain_count+  - Integer. Specifies the fault domain count of availability set.
    #
    def create_availability_set(avset_params)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_AVAILABILITY_SETS, avset_params[:name])
      availability_set = {
        'name'       => avset_params[:name],
        'type'       => "#{REST_API_PROVIDER_COMPUTER}/#{REST_API_COMPUTER_AVAILABILITY_SETS}",
        'location'   => avset_params[:location],
        'tags'       => avset_params[:tags],
        'properties' => {
          'platformUpdateDomainCount' => avset_params[:platform_update_domain_count],
          'platformFaultDomainCount'  => avset_params[:platform_fault_domain_count]
        }
      }
      http_put(url, availability_set)
    end

    def get_availability_set_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_AVAILABILITY_SETS, name)
      get_availability_set(url)
    end

    def get_availability_set(url)
      availability_set = nil
      result = get_resource_by_id(url)
      unless result.nil?
        availability_set = {}
        availability_set[:id]       = result['id']
        availability_set[:name]     = result['name']
        availability_set[:location] = result['location']
        availability_set[:tags]     = result['tags']

        properties = result['properties']
        availability_set[:platform_update_domain_count] = properties['platformUpdateDomainCount']
        availability_set[:platform_fault_domain_count]  = properties['platformFaultDomainCount']
        availability_set[:virtual_machines]             = []

        unless properties['virtualMachines'].nil?
          properties['virtualMachines'].each do |vm|
            availability_set[:virtual_machines].push({:id => vm["id"]})
          end
        end
      end
      availability_set
    end

    def delete_availability_set(name)
      @logger.debug("delete_availability_set - trying to delete #{name}")
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_AVAILABILITY_SETS, name)
      http_delete(url)
    end

    # Network/Public IP
    def create_public_ip(name, location, is_static = true)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_PUBLIC_IP_ADDRESSES, name)
      public_ip = {
        'name'       => name,
        'location'   => location,
        'properties' => {
          'publicIPAllocationMethod' => is_static ? 'Static' : 'Dynamic'
        }
      }
      http_put(url, public_ip)
    end

    def get_public_ip_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_PUBLIC_IP_ADDRESSES, name)
      get_public_ip(url)
    end

    def get_public_ip(url)
      ip_address = nil
      result = get_resource_by_id(url)
      unless result.nil?
        ip_address = {}
        ip_address[:id]       = result['id']
        ip_address[:name]     = result['name']
        ip_address[:location] = result['location']

        properties = result['properties']
        ip_address[:provisioning_state]          = properties['provisioningState']
        ip_address[:ip_address]                  = properties['ipAddress']
        ip_address[:public_ip_allocation_method] = properties['publicIPAllocationMethod']
        ip_address[:ip_configuration_id]         = properties['ipConfigurations']['id'] unless properties['ipConfigurations'].nil?
        unless properties['dnsSettings'].nil?
          ip_address[:domain_name_label] = properties['dnsSettings']['domainNameLabel']
          ip_address[:fqdn]              = properties['dnsSettings']['fqdn']
        end
      end
      ip_address
    end

    def list_public_ips()
      ip_addresses = []
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_PUBLIC_IP_ADDRESSES)
      result = get_resource_by_id(url)
      unless result.nil?
        result['value'].each do |ret|
          ip_address = {}
          ip_address[:id]       = ret['id']
          ip_address[:name]     = ret['name']
          ip_address[:location] = ret['location']

          properties = ret['properties']
          ip_address[:provisioning_state]          = properties['provisioningState']
          ip_address[:ip_address]                  = properties['ipAddress']
          ip_address[:public_ip_allocation_method] = properties['publicIPAllocationMethod']
          ip_address[:ip_configuration_id]         = properties['ipConfigurations']['id'] unless properties['ipConfigurations'].nil?
          unless properties['dnsSettings'].nil?
            ip_address[:domain_name_label] = properties['dnsSettings']['domainNameLabel']
            ip_address[:fqdn]              = properties['dnsSettings']['fqdn']
          end
          ip_addresses.push(ip_address)
        end
      end
      ip_addresses
    end

    def delete_public_ip(name)
      @logger.debug("delete_public_ip - trying to delete #{name}")
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_PUBLIC_IP_ADDRESSES, name)
      http_delete(url)
    end

    # Network/Load Balancer
    def create_load_balancer(name,  public_ip, tags, tcp_endpoints = [], udp_endpoints = [])
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_LOAD_BALANCERS, name)
      load_balancer = {
        'name'       => name,
        'location'   => public_ip[:location],
        'tags'       => tags,
        'properties' => {
          'frontendIPConfigurations' => [
            'name'        => 'LBFE',
            'properties'  => {
              #'privateIPAllocationMethod' => 'Dynamic',
              'publicIPAddress'           => {
                'id' => public_ip[:id]
              }
            }
          ],
          'backendAddressPools'      => [
            'name'        => 'LBBE'
          ],
          'inboundNatRules'          => [],
        }
      }

      frontend_ip_configuration_id = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_LOAD_BALANCERS, name, 'frontendIPConfigurations/LBFE')
      tcp_endpoints.each do |endpoint|
        ports = endpoint.split(':')
        inbound_nat_rules = {
          'name'        => "NatRule-TcpEndPoints-#{ports[0]}",
          'properties'  => {
            'frontendPort'        => ports[0],
            'backendPort'         => ports[1],
            'enableFloatingIP'    => false,
            'protocol'            => 'Tcp',
            'frontendIPConfiguration' => {
              "id" => frontend_ip_configuration_id
            }
          }
        }
        load_balancer['properties']['inboundNatRules'].push(inbound_nat_rules)
      end
      udp_endpoints.each do |endpoint|
        ports = endpoint.split(':')
        inbound_nat_rules = {
          'name' => "NatRule-UdpEndPoints-#{ports[0]}",
          'properties'  => {
            'frontendPort'        => ports[0],
            'backendPort'         => ports[1],
            'enableFloatingIP'    => false,
            'protocol'            => 'Udp',
            'frontendIPConfiguration' => {
              "id" => frontend_ip_configuration_id
            }
          }
        }
        load_balancer['properties']['inboundNatRules'].push(inbound_nat_rules)
      end

      http_put(url, load_balancer)
    end

    def get_load_balancer_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_LOAD_BALANCERS, name)
      get_load_balancer(url)
    end

    def get_load_balancer(url)
      load_balancer = nil
      result = get_resource_by_id(url)
      unless result.nil?
        load_balancer = {}
        load_balancer[:id] = result['id']
        load_balancer[:name] = result['name']
        load_balancer[:location] = result['location']
        load_balancer[:tags] = result['tags']

        properties = result['properties']
        load_balancer[:provisioning_state] = properties['provisioningState']

        frontend = properties['frontendIPConfigurations']
        load_balancer[:frontend_ip_configurations] = []
        frontend.each do |frontend_ip|
          ip = {}
          ip[:name]                         = frontend_ip['name']
          ip[:id]                           = frontend_ip['id']
          ip[:provisioning_state]           = frontend_ip['properties']['provisioningState']
          ip[:private_ip_allocation_method] = frontend_ip['properties']['privateIPAllocationMethod']
          ip[:private_ip]                   = frontend_ip['properties']['privateIPAddress'] unless frontend_ip['properties']['privateIPAddress'].nil?
          ip[:public_ip]                    = get_public_ip(frontend_ip['properties']['publicIPAddress']['id']) unless frontend_ip['properties']['publicIPAddress'].nil?
          ip[:inbound_nat_rules]            = frontend_ip['properties']['inboundNatRules']
          load_balancer[:frontend_ip_configurations].push(ip)
        end

        backend = properties['backendAddressPools']
        load_balancer[:backend_address_pools] = []
        backend.each do |backend_ip|
          ip = {}
          ip[:name]                         = backend_ip['name']
          ip[:id]                           = backend_ip['id']
          ip[:provisioning_state]           = backend_ip['properties']['provisioningState']
          ip[:backend_ip_configurations]    = backend_ip['properties']['backendIPConfigurations']
          load_balancer[:backend_address_pools].push(ip)
        end
      end
      load_balancer
    end

    def delete_load_balancer(name)
      @logger.debug("delete_load_balancer - trying to delete #{name}")
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_LOAD_BALANCERS, name)
      http_delete(url)
    end

    # Network/Network Interface
    # Public: Create a network interface based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [Hash] nic_params    - Parameters for creating the network interface.
    # @param [Hash] subnet        - The subnet which the network interface is binded to.
    # @param [Hash] tags          - The tags of the network interface.
    # @param [Hash] load_balancer - The load balancer which the network interface is binded to.
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+          - String. Name of network interface.
    # * +:location+      - String. The location where the network interface will be created.
    # * +:private_ip     - String. Private IP address which the network interface will use.
    # * +:dns_servers    - Array. DNS servers. 
    # * +:public_ip      - Hash. The public IP which the network interface is binded to.
    # * +:security_group - Hash. The network security group which the network interface is binded to.
    #
    def create_network_interface(nic_params, subnet, tags, load_balancer = nil)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, nic_params[:name])
      interface = {
        'name'       => nic_params[:name],
        'location'   => nic_params[:location],
        'tags'       => tags,
        'properties' => {
          'networkSecurityGroup' => {
            'id' => nic_params[:security_group][:id]
          },
          'ipConfigurations' => [
            {
              'name'        => 'ipconfig1',
              'properties'  => {
                'privateIPAddress'          => nic_params[:private_ip], 
                'privateIPAllocationMethod' => nic_params[:private_ip].nil? ? 'Dynamic' : 'Static',
                'publicIPAddress'           => nic_params[:public_ip].nil? ? nil : { 'id' => nic_params[:public_ip][:id] },
                'subnet' => {
                  'id' => subnet[:id]
                }
              }
            }
          ],
          'dnsSettings'      => {
            'dnsServers' => nic_params[:dns_servers].nil? ? [] : nic_params[:dns_servers]
          }
        }
      }

      unless load_balancer.nil?
        interface['properties']['ipConfigurations'][0]['properties']['loadBalancerBackendAddressPools'] = [
          {
            'id' => load_balancer[:backend_address_pools][0][:id]
          }
        ]
        interface['properties']['ipConfigurations'][0]['properties']['loadBalancerInboundNatRules'] = 
          load_balancer[:frontend_ip_configurations][0][:inbound_nat_rules]
      end

      http_put(url, interface)
    end

    def get_network_interface_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, name)
      get_network_interface(url)
    end

    def get_network_interface(url)
      interface = nil
      result = get_resource_by_id(url)
      unless result.nil?
        interface = {}
        interface[:id] = result['id']
        interface[:name] = result['name']
        interface[:location] = result['location']
        interface[:tags] = result['tags']

        properties = result['properties']
        interface[:provisioning_state] = properties['provisioningState']
        unless properties['dnsSettings']['dnsServers'].nil?
          interface[:dns_settings] = []
          properties['dnsSettings']['dnsServers'].each { |dns| interface[:dns_settings].push(dns) }
        end

        ip_configuration = properties['ipConfigurations'][0]
        interface[:ip_configuration_id] = ip_configuration['id']

        ip_configuration_properties = ip_configuration['properties']
        interface[:private_ip] = ip_configuration_properties['privateIPAddress']
        interface[:private_ip_allocation_method] = ip_configuration_properties['privateIPAllocationMethod']
        unless ip_configuration_properties['publicIPAddress'].nil?
          interface[:public_ip] = get_public_ip(ip_configuration_properties['publicIPAddress']['id'])
        end
        unless ip_configuration_properties['loadBalancerBackendAddressPools'].nil?
          names = parse_name_from_id(ip_configuration_properties['loadBalancerBackendAddressPools'][0]['id'])
          interface[:load_balancer] = get_load_balancer_by_name(names[:resource_name])
        end
      end
      interface
    end

    def delete_network_interface(name)
      @logger.debug("delete_network_interface - trying to delete #{name}")
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, name)
      http_delete(url)
    end

    # Network/Subnet
    def get_network_subnet_by_name(vnet_name, subnet_name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_VNETS, vnet_name, "subnets/#{subnet_name}")
      get_network_subnet(url)
    end

    def get_network_subnet(url)
      subnet = nil
      result = get_resource_by_id(url)
      unless result.nil?
        subnet = {}
        subnet[:id]   = result['id']
        subnet[:name] = result['name']

        properties = result['properties']
        subnet[:provisioning_state] = properties['provisioningState']
        subnet[:address_prefix]     = properties['addressPrefix']
      end
      subnet
    end

    # Network/Network Security Group
    def get_network_security_group_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_SECURITY_GROUPS, name)
      get_network_security_group(url)
    end

    def get_network_security_group(url)
      nsg = nil
      result = get_resource_by_id(url)
      unless result.nil?
        nsg = {}
        nsg[:id]   = result['id']
        nsg[:name] = result['name']
        nsg[:location] = result['location']
        nsg[:tags] = result['tags']

        properties = result['properties']
        nsg[:provisioning_state] = properties['provisioningState']
      end
      nsg
    end
    
    # Storage/StorageAccounts
    # https://msdn.microsoft.com/en-us/library/azure/mt163564.aspx
    def create_storage_account(name, location, account_type, tags)
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name)
      storage_account = {
        'location'   => location,
        'tags'       => tags,
        'properties' => {
          'accountType' => account_type
        }
      }

      uri = http_url(url)
      @logger.info("create_storage_account - trying to put #{uri}")

      request = Net::HTTP::Put.new(uri.request_uri)
      request_body = storage_account.to_json
      request.body = request_body
      request['Content-Length'] = request_body.size
      @logger.debug("create_storage_account - request body:\n#{request.body}")

      retry_after = 10
      response = http_get_response(uri, request, retry_after)
      if response.code.to_i == HTTP_CODE_OK
        return true
      elsif response.code.to_i != HTTP_CODE_ACCEPTED
        raise AzureError, "create_storage_account - Cannot create the storage account \"#{name}\". http code: #{response.code}."
      end

      @logger.debug("create_storage_account - storage asynchronous operation: #{response['Location']}")
      uri = URI(response['Location'])
      api_version = get_api_version(@azure_properties, AZURE_RESOUCE_PROVIDER_STORAGE)
      params = {
        'api-version' => api_version
      }
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri.request_uri)
      request.add_field('x-ms-version', api_version)
      while true
        retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
        sleep(retry_after)

        @logger.debug("create_storage_account - trying to get the status of asynchronous operation: #{uri}")
        response = http_get_response(uri, request, retry_after, true)

        status_code = response.code.to_i
        if status_code == HTTP_CODE_OK
          return true
        elsif status_code == HTTP_CODE_INTERNALSERVERERROR
          error = "create_storage_account - http code: #{response.code}"
          error += " message: #{response.body}" unless response.body.nil?
          @logger.warn(error)
        elsif status_code != HTTP_CODE_ACCEPTED
          raise AzureError, "create_storage_account - http code: #{response.code}"
        end
      end
    end

    def check_storage_account_name_availability(name)
      url =  "/subscriptions/#{URI.escape(@azure_properties['subscription_id'])}"
      url += "/providers/#{REST_API_PROVIDER_STORAGE}"
      url += '/checkNameAvailability'
      storage_account = {
        'name' => name,
        'type' => "#{REST_API_PROVIDER_STORAGE}/#{REST_API_STORAGE_ACCOUNTS}",
      }

      result = http_post(url, storage_account)
      raise AzureError, "Cannot check the availability of the storage account name \"#{name}\"." if result.nil?
      ret = {
        :available => result['nameAvailable'],
        :reason    => result['reason'],
        :message   => result['message']
      }
      ret
    end

    def get_storage_account_by_name(name)
      url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name)
      get_storage_account(url)
    end

    def get_storage_account(url)
      storage_account = nil
      result = get_resource_by_id(url)
      unless result.nil?
        storage_account = {}
        storage_account[:id]        = result['id']
        storage_account[:name]      = result['name']
        storage_account[:location]  = result['location']

        properties = result['properties']
        storage_account[:provisioning_state] = properties['provisioningState']
        storage_account[:account_type]       = properties['accountType']
        storage_account[:storage_blob_host]  = properties['primaryEndpoints']['blob']
        if properties['primaryEndpoints'].has_key?('table')
          storage_account[:storage_table_host] = properties['primaryEndpoints']['table']
        end
      end
      storage_account
    end

    def get_storage_account_keys_by_name(name)
      result = nil
      begin
        url = rest_api_url(REST_API_PROVIDER_STORAGE, REST_API_STORAGE_ACCOUNTS, name, 'listKeys')
        result = http_post(url)
      rescue AzureNoFoundError => e
        result = nil
      end

      keys = []
      unless result.nil?
        keys << result['key1']
        keys << result['key2']
      end
      keys
    end

    private

    def http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      # The default value for read_timeout is 60 seconds.
      # The default value for open_timeout is nil before ruby 2.3.0 so set it to 60 seconds here.
      http.open_timeout = 60
      # Uncomment below line for debug
      #http.set_debug_output($stdout)
      http
    end

    def get_token(force_refresh = false)
      if @token.nil? || (Time.at(@token['expires_on'].to_i) - Time.now) <= 0 || force_refresh
        @logger.info("get_token - trying to get/refresh Azure authentication token")
        endpoint, api_version = get_azure_authentication_endpoint_and_api_version(@azure_properties)
        params = {}
        params['api-version'] = api_version

        uri = URI(endpoint)
        uri.query = URI.encode_www_form(params)

        params = {}
        params['grant_type']    = 'client_credentials'
        params['client_id']     = @azure_properties['client_id']
        params['client_secret'] = @azure_properties['client_secret']
        params['resource']      = get_token_resource(@azure_properties)
        params['scope']         = 'user_impersonation'

        @logger.debug("get_token - authentication_endpoint: #{uri}")
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body = URI.encode_www_form(params)
        @logger.debug("get_token - request.header:")
        request.each_header { |k,v| @logger.debug("\t#{k} = #{v}") }
        @logger.debug("get_token - request.body:\n#{request.body}")

        response = http(uri).request(request)
        if response.code.to_i == HTTP_CODE_OK
          @token = JSON(response.body)
          @logger.debug("get_token - token is\n#{@token}")
        elsif response.code.to_i == HTTP_CODE_UNAUTHORIZED
          raise AzureError, "get_token - http code: #{response.code}. Azure authentication failed: Invalid tenant id, client id or client secret."
        elsif response.code.to_i == HTTP_CODE_BADREQUEST
          raise AzureError, "get_token - http code: #{response.code}. Azure authentication failed: Bad request. Please assure no typo in values of tenant id, client id or client secret."
        else
          raise AzureError, "get_token - http code: #{response.code}"
        end
      end

      @token['access_token']
    end

    def http_url(url, params = {})
      unless params.has_key?('api-version')
        resource_provider = nil
        if url.include?(REST_API_PROVIDER_COMPUTER)
          resource_provider = AZURE_RESOUCE_PROVIDER_COMPUTER
        elsif url.include?(REST_API_PROVIDER_NETWORK)
          resource_provider = AZURE_RESOUCE_PROVIDER_NETWORK
        elsif url.include?(REST_API_PROVIDER_STORAGE)
          resource_provider = AZURE_RESOUCE_PROVIDER_STORAGE
        else
          resource_provider = AZURE_RESOUCE_PROVIDER_GROUP
        end
        params['api-version'] = get_api_version(@azure_properties, resource_provider)
      end
      uri = URI(get_arm_endpoint(@azure_properties) + url)
      uri.query = URI.encode_www_form(params)
      uri
    end

    def http_get_response(uri, request, retry_after, is_async = false)
      response = nil
      refresh_token = false
      retry_count = 0

      begin
        request['User-Agent']    = USER_AGENT
        request['Content-Type']  = 'application/json'
        request['Authorization'] = 'Bearer ' + get_token(refresh_token)
        response = http(uri).request(request)

        retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
        status_code = response.code.to_i
        @logger.debug("http_get_response - #{retry_count}: #{status_code}\n#{response.body}")
        if status_code == HTTP_CODE_UNAUTHORIZED
          raise AzureUnauthorizedError, "http_get_response - Azure authentication failed: Token is invalid."
        end
        refresh_token = false
        if status_code == HTTP_CODE_OK && is_async
          # Need to check status in response body for asynchronous operation even if status_code is HTTP_CODE_OK.
          result = JSON(response.body)
          if result['status'] == 'Failed'
            error = "http_get_response - http code: #{response.code}\n"
            error += " message: #{response.body}"
            raise AzureAsynInternalError, error
          end
        elsif AZURE_RETRY_ERROR_CODES.include?(status_code)
          error = "http_get_response - http code: #{response.code}\n"
          error += " message: #{response.body}"
          raise AzureInternalError, error
        end
      rescue AzureUnauthorizedError => e
        unless refresh_token
          refresh_token = true
          retry
        end
        raise e
      rescue AzureInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          @logger.warn("http_get_response - Fail for an AzureInternalError. Will retry after #{retry_after} seconds.")
          retry_count += 1
          sleep(retry_after)
          retry
        end
        raise e
      rescue AzureAsynInternalError => e
        @logger.warn("http_get_response - Fail for an AzureAsynInternalError. Will retry after #{retry_after} seconds.")
        sleep(retry_after)
        raise e
      rescue Net::OpenTimeout => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          @logger.warn("http_get_response - Fail for an OpenTimeout. Will retry after #{retry_after} seconds.")
          retry_count += 1
          sleep(retry_after)
          retry
        end
        raise e
      rescue => e
        # Below error message depends on require "resolv-replace.rb" in lib/cloud/azure.rb
        if e.inspect.include?('SocketError: Hostname not known') && retry_count < AZURE_MAX_RETRY_COUNT
          @logger.warn("http_get_response - Fail for a DNS resolve error. Will retry after #{retry_after} seconds.")
          retry_count += 1
          sleep(retry_after)
          retry
        end
        cloud_error("http_get_response - #{e.inspect}\n#{e.backtrace.join("\n")}")
      end
      response
    end

    def check_completion(response, options)
      @logger.debug("check_completion - response code: #{response.code} azure-asyncoperation: #{response['azure-asyncoperation']} response.body: \n#{response.body}")

      operation_status_link = response['azure-asyncoperation']
      if options[:return_code].include?(response.code.to_i)
        if operation_status_link.nil?
          result = true
          ignore_exception{ result = JSON(response.body) } unless response.body.nil? || response.body.empty?
          return result
        end
      elsif !options[:success_code].include?(response.code.to_i)
        error = "#{options[:operation]} - http code: #{response.code}"
        error += " message: #{response.body}" unless response.body.nil?
        raise AzureConflictError, error if response.code.to_i == HTTP_CODE_CONFLICT
        raise AzureError, error
      end

      retry_after = options[:retry_after]
      operation_status_link.gsub!(' ', '%20')
      uri = URI(operation_status_link)
      params = {}
      params['api-version'] = options[:api_version]
      request = Net::HTTP::Get.new(uri.request_uri)
      uri.query = URI.encode_www_form(params)
      request.add_field('x-ms-version', options[:api_version])
      while true
        retry_after = response['Retry-After'].to_i if response.key?('Retry-After')
        sleep(retry_after)

        @logger.debug("check_completion - trying to get the status of asynchronous operation: #{uri}")
        response = http_get_response(uri, request, retry_after, true)
        status_code = response.code.to_i
        if status_code != HTTP_CODE_OK && status_code != HTTP_CODE_ACCEPTED
          raise AzureError, "check_completion - http code: #{response.code}"
        end

        unless response.body.nil?
          ret = JSON(response.body)
          unless ret['status'].nil?
            if ret['status'] != 'InProgress'
              if ret['status'] == 'Succeeded'
                return true
              else
                error_msg = "status: #{ret['status']}\n"
                error_msg += "http code: #{status_code}\n"
                error_msg += "request id: #{response['x-ms-request-id']}\n"
                error_msg += "error:\n#{ret['error']}"
                raise AzureError, error_msg
              end
            else
              @logger.debug("check_completion - InProgress...")
            end
          end
        end
      end
    end

    def http_get(url, params = {}, retry_after = 5)
      uri = http_url(url, params)
      @logger.info("http_get - trying to get #{uri}")

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http_get_response(uri, request, retry_after)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_OK
        if status_code == HTTP_CODE_NOCONTENT
          raise AzureNoFoundError, "http_get - http code: #{response.code}"
        elsif status_code == HTTP_CODE_NOTFOUND
          raise AzureNoFoundError, "http_get - http code: #{response.code}"
        else
          error = "http_get - http code: #{response.code}"
          error += " message: #{response.body}" unless response.body.nil?
          raise AzureError, error
        end
      end

      result = nil
      result = JSON(response.body) unless response.body.nil?
    end

    def http_put(url, body = nil, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_put - #{retry_count}: trying to put #{uri}")

        request = Net::HTTP::Put.new(uri.request_uri)
        unless body.nil?
          request_body = body.to_json
          request.body = request_body
          request['Content-Length'] = request_body.size
          @logger.debug("http_put - request body:\n#{request.body}")
        end

        response = http_get_response(uri, request, retry_after)
        options = {
          :operation    => 'http_put',
          :return_code => [HTTP_CODE_OK],
          :success_code => [HTTP_CODE_CREATED],
          :api_version  => params['api-version'],
          :retry_after  => retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    def http_delete(url, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_delete - #{retry_count}: trying to delete #{uri}")

        request = Net::HTTP::Delete.new(uri.request_uri)
        response = http_get_response(uri, request, retry_after)
        options = {
          :operation    => 'http_delete',
          :return_code => [HTTP_CODE_OK, HTTP_CODE_NOCONTENT],
          :success_code => [HTTP_CODE_ACCEPTED],
          :api_version  => params['api-version'],
          :retry_after  => retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end

    def http_post(url, body = nil, params = {}, retry_after = 5)
      uri = http_url(url, params)
      retry_count = 0

      begin
        @logger.info("http_post - #{retry_count}: trying to post #{uri}")

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Length'] = 0
        unless body.nil?
          request_body = body.to_json
          request.body = request_body
          request['Content-Length'] = request_body.size
          @logger.debug("http_put - request body:\n#{request.body}")
        end
        response = http_get_response(uri, request, retry_after)
        options = {
          :operation    => 'http_post',
          :return_code => [HTTP_CODE_OK],
          :success_code => [HTTP_CODE_ACCEPTED],
          :api_version  => params['api-version'],
          :retry_after  => retry_after
        }
        check_completion(response, options)
      rescue AzureAsynInternalError => e
        if retry_count < AZURE_MAX_RETRY_COUNT
          retry_count += 1
          retry
        end
        raise e
      end
    end
  end
end
