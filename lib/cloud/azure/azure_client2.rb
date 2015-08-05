###############################################################################
# This client is for using Azure Resource Manager. It will be obsoleted soon
# after azure-sdk-for-ruby supports Azure Resource Manager.
###############################################################################
module Bosh::AzureCloud
  class AzureError < Bosh::Clouds::CloudError; end
  class AzureUnauthorizedError < AzureError; end
  class AzureNoFoundError < AzureError; end

  class AzureClient2
    include Helpers

    API_VERSION    = '2015-05-01-preview'
    API_VERSION_1  = '2015-01-01'

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

    REST_API_PROVIDER_COMPUTER           = 'Microsoft.Compute'
    REST_API_COMPUTER_VIRTUAL_MACHINES   = 'virtualMachines'

    REST_API_PROVIDER_NETWORK            = 'Microsoft.Network'
    REST_API_NETWORK_PUBLIC_IP_ADDRESSES = 'publicIPAddresses'
    REST_API_NETWORK_LOAD_BALANCERS      = 'loadBalancers'
    REST_API_NETWORK_INTERFACES          = 'networkInterfaces'
    REST_API_NETWORK_VNETS               = 'virtualNetworks'

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
      params = { 'api-version' => API_VERSION_1}
      result = get_resource_by_id(url, params)

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
    #
    #  ==== Params
    #
    # Accepted key/value pairs are:
    # * +:name+                 - String. Name of virtual machine.
    # * +:location+             - String. The location where the virtual machine will be created.
    # * +:vm_size+              - String. Specifies the size of the virtual machine instance.
    # * +:username+             - String. User name for the virtual machine instance.
    # * +:custom_data+          - String. Specifies a base-64 encoded string of custom data. 
    # * +:image_uri+            - String. The URI of the image.
    # * +:os_disk_name+         - String. The name of the OS disk for the virtual machine instance.
    # * +:os_vhd_uri+           - String. The URI of the OS disk for the virtual machine instance.
    # * +:ssh_cert_data+        - String. The content of SSH certificate.
    #
    def create_virtual_machine(vm_params, network_interface)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, vm_params[:name])
      vm = {
        'name'       => vm_params[:name],
        'location'   => vm_params[:location],
        'type'       => "#{REST_API_PROVIDER_COMPUTER}/#{REST_API_COMPUTER_VIRTUAL_MACHINES}",
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
              'caching'      => 'ReadWrite',
              'image'        => {
                'uri' => vm_params[:image_uri]
              },
              'vhd'          => {
                'uri' => vm_params[:os_vhd_uri]
              }
            },
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
      params = {
        'validating' => 'true'
      }
      http_put(url, vm, 30, params)
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
      result = get_resource_by_id(url)
      if result.nil?
        raise AzureNoFoundError, "update_tags_of_virtual_machine - cannot find the virtual machine by name \"#{name}\""
      end

      result['tags'] = tags
      http_put(url, result)
    end

    def attach_disk_to_virtual_machine(name, disk_name, disk_uri)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      result = get_resource_by_id(url)
      if result.nil?
        raise AzureNoFoundError, "attach_disk_to_virtual_machine - cannot find the virtual machine by name \"#{name}\""
      end

      lun = 0
      data_disks = result['properties']['storageProfile']['dataDisks']
      for i in 0..128
        disk = data_disks.find { |disk| disk['lun'] == i}
        if disk.nil?
          lun = i
          break
        end
      end

      new_disk = {
        'name'         => disk_name,
        'lun'          => lun,
        'createOption' => 'Attach',
        'caching'      => 'ReadWrite',
        'vhd'          => { 'uri' => disk_uri }
      }
      result['properties']['storageProfile']['dataDisks'].push(new_disk)
      @logger.info("attach_disk_to_virtual_machine - attach disk #{disk_name} to #{lun}")
      http_put(url, result)
      disk = {
        :name         => disk_name,
        :lun          => lun,
        :createOption => 'Attach',
        :caching      => 'ReadWrite',
        :vhd          => { :uri => disk_uri }
      }
    end

    def detach_disk_from_virtual_machine(name, disk_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTER, REST_API_COMPUTER_VIRTUAL_MACHINES, name)
      result = get_resource_by_id(url)
      if result.nil?
        raise AzureNoFoundError, "detach_disk_from_virtual_machine - cannot find the virtual machine by name \"#{name}\""
      end

      disk = result['properties']['storageProfile']['dataDisks'].find { |disk| disk['name'] == disk_name}
      raise Bosh::Clouds::DiskNotAttached.new(true),
        "The disk #{disk_name} is not attached to the virtual machine #{name}" if disk.nil?

      result['properties']['storageProfile']['dataDisks'].delete_if { |disk| disk['name'] == disk_name}

      @logger.info("detach_disk_from_virtual_machine - detach disk #{disk_name} from lun #{disk['lun']}")
      http_put(url, result)
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
      http_delete(url, nil, 10)
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
      http_put(url, public_ip, 10)
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
      http_delete(url, nil, 10)
    end

    # Network/Load Balancer
    def create_load_balancer(name,  public_ip, tcp_endpoints = [], udp_endpoints = [])
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_LOAD_BALANCERS, name)
      load_balancer = {
        'name'       => name,
        'location'   => public_ip[:location],
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
          'name'        => "NatRule-TcpEndPoints-#{ports[0].to_s}",
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
          'name' => "NatRule-UdpEndPoints-#{ports[0].to_s}",
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

      http_put(url, load_balancer, 10)
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
          ip[:public_ip]                    = get_public_ip(frontend_ip['properties']['publicIPAddress']['id'])
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
      http_delete(url, nil, 10)
    end

    # Network/Network Interface
    # Public: Create a network interface based on the supplied configuration.
    #
    # ==== Attributes
    #
    # @param [Hash] nic_params    - Parameters for creating the network interface.
    # @param [Hash] subnet        - The subnet which the network interface is binded to.
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
    #
    def create_network_interface(nic_params, subnet, load_balancer = nil)
      url = rest_api_url(REST_API_PROVIDER_NETWORK, REST_API_NETWORK_INTERFACES, nic_params[:name])
      interface = {
        'name'       => nic_params[:name],
        'location'   => nic_params[:location],
        'properties' => {
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

      http_put(url, interface, 10)
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
      http_delete(url, nil, 10)
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

    # Storage/StorageAccounts
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
        storage_account[:primary_endpoints]  = properties['primaryEndpoints']
      end
      storage_account
    end

    private

    def http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      # Uncomment below line for debug
      #http.set_debug_output($stdout)
      http
    end

    def get_token(force_refresh = false)
      if @token.nil? || (Time.at(@token['expires_on'].to_i) - Time.now) <= 0 || force_refresh
        @logger.info("get_token - trying to get/refresh Azure authentication token")
        params = {}
        params['api-version'] = API_VERSION

        uri = URI(AZURE_ENVIRONMENTS[@azure_properties['environment']]['activeDirectoryEndpointUrl'] + '/' + @azure_properties['tenant_id'] + '/oauth2/token')
        uri.query = URI.encode_www_form(params)

        params = {}
        params['grant_type']    = 'client_credentials'
        params['client_id']     = @azure_properties['client_id']
        params['client_secret'] = @azure_properties['client_secret']
        params['resource']      = AZURE_ENVIRONMENTS[@azure_properties['environment']]['resourceManagerEndpointUrl']
        params['scope']         = 'user_impersonation'

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body = URI.encode_www_form(params)

        response = http(uri).request(request)
        if response.code.to_i == HTTP_CODE_OK
          @token = JSON(response.body)
          @logger.debug("get_token - token is\n#{@token}")
        else
          raise AzureError, "get_token - http error: #{response.code}"
        end
      end

      @token['access_token']
    end

    def http_url(url, params = {})
      uri = URI(AZURE_ENVIRONMENTS[@azure_properties['environment']]['resourceManagerEndpointUrl'] + url)
      params['api-version'] = API_VERSION if params['api-version'].nil?
      uri.query = URI.encode_www_form(params)
      uri
    end

    def http_get_response(uri, request)
      response = nil
      refresh_token = false
      begin
        request['Content-Type']  = 'application/json'
        request['Authorization'] = 'Bearer ' + get_token(refresh_token)
        response = http(uri).request(request)
        if response.code.to_i == HTTP_CODE_UNAUTHORIZED
          raise AzureUnauthorizedError, "http_get_response - Azure authentication failed: Token is invalid."
        end
      rescue AzureUnauthorizedError => e
        unless refresh_token
          refresh_token = true
          retry
        end
        raise e
      rescue => e
        cloud_error("http_get_response - #{e.message}\n#{e.backtrace.join("\n")}")
      end
      response
    end

    def check_completion(response, api_version, retry_after = 30)
      @logger.debug("check_completion - response code: #{response.code} response.body: \n#{response.body}")
      retry_after = response['retry-after'].to_i if response.key?('retry-after')
      operation_status_link = response['azure-asyncoperation']
      if operation_status_link.nil? || operation_status_link.empty?
        raise AzureError, "check_completion - operation_status_link cannot be null."
      end
      operation_status_link.gsub!(' ', '%20')

      uri = URI(operation_status_link)
      params = {}
      params['api-version'] = api_version
      request = Net::HTTP::Get.new(uri.request_uri)
      uri.query = URI.encode_www_form(params)
      request.add_field('x-ms-version', api_version)
      while true
        sleep(retry_after)

        @logger.debug("check_completion - trying to get the status of asynchronous operation: #{uri.to_s}")
        response = http_get_response(uri, request)
        status_code = response.code.to_i
        @logger.debug("check_completion - #{status_code}\n#{response.body}")
        if status_code != HTTP_CODE_OK && status_code != HTTP_CODE_ACCEPTED
          raise AzureError, "check_completion - http error: #{response.code}"
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

    def http_get(url, params = {})
      uri = http_url(url, params)
      @logger.info("http_get - trying to get #{uri.to_s}")

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http_get_response(uri, request)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_OK
        if status_code == HTTP_CODE_NOCONTENT
          raise AzureNoFoundError, "http_get - error: #{response.code}"
        elsif status_code == HTTP_CODE_NOTFOUND
          raise AzureNoFoundError, "http_get - error: #{response.code}"
        else
          error = "http_get - error: #{response.code}"
          error += " message: #{response.body}" unless response.body.nil?
          raise AzureError, error
        end
      end

      result = nil
      result = JSON(response.body) unless response.body.nil?
    end

    def http_put(url, body = nil, retry_after = 30, params = {})
      uri = http_url(url, params)
      @logger.info("http_put - trying to put #{uri.to_s}")

      request = Net::HTTP::Put.new(uri.request_uri)
      unless body.nil?
        request_body = body.to_json
        request.body = request_body
        request['Content-Length'] = request_body.size
        @logger.debug("http_put - request body:\n#{request.body}")
      end
      response = http_get_response(uri, request)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_OK && status_code != HTTP_CODE_CREATED
        error = "http_put - error: #{response.code}"
        error += " message: #{response.body}" unless response.body.nil?
        raise AzureError, error
      end
      api_version = API_VERSION
      api_version = params['api-version'] unless params['api-version'].nil?
      check_completion(response, api_version, retry_after)
    end

    def http_delete(url, body = nil, retry_after = 10, params = {})
      uri = http_url(url, params)
      @logger.info("http_delete - trying to delete #{uri.to_s}")

      request = Net::HTTP::Delete.new(uri.request_uri)
      unless body.nil?
        request_body = body.to_json
        request.body = request_body
        request['Content-Length'] = request_body.size
        @logger.debug("http_put - request body:\n#{request.body}")
      end
      response = http_get_response(uri, request)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_OK && status_code != HTTP_CODE_ACCEPTED && status_code != HTTP_CODE_NOCONTENT
        error = "http_delete - error: #{response.code}"
        error += " message: #{response.body}" unless response.body.nil?
        raise AzureError, error
      end

      return true if status_code == HTTP_CODE_OK || status_code == HTTP_CODE_NOCONTENT

      api_version = API_VERSION
      api_version = params['api-version'] unless params['api-version'].nil?
      check_completion(response, api_version, retry_after)
    end

    def http_post(url, body = nil, retry_after = 30, params = {})
      uri = http_url(url, params)
      @logger.info("http_post - trying to post #{uri.to_s}")

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Length'] = 0
      unless body.nil?
        request_body = body.to_json
        request.body = request_body
        request['Content-Length'] = request_body.size
        @logger.debug("http_put - request body:\n#{request.body}")
      end
      response = http_get_response(uri, request)
      status_code = response.code.to_i
      if status_code != HTTP_CODE_ACCEPTED
        error = "http_post - error: #{response.code}"
        error += " message: #{response.body}" unless response.body.nil?
        raise AzureError, error
      end
      api_version = API_VERSION
      api_version = params['api-version'] unless params['api-version'].nil?
      check_completion(response, api_version, retry_after)
    end
  end
end
