# frozen_string_literal: true

module Bosh::AzureCloud
  class AzureClient
    # VMSS related starts

    # Get the information for the vmss
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vmss_name  - Name of the vmss
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesets/get
    #
    def get_vmss_by_name(resource_group_name, vmss_name)
      vmss = nil
      result = _get_vmss_by_name(resource_group_name, vmss_name)
      unless result.nil?
        vmss = {}
        vmss[:location] = result['location']
        vmss[:sku] = {}
        vmss[:sku][:name] = result['sku']['name']
        vmss[:zones] = result['zones']
      end
      vmss
    end

    # Create one vmss
    #
    # @param [String] resource_group_name  - Name of resource group.
    # @param [Hash] vm_params  - parameters for creating the vmss
    # @param [Array] network_interfaces   - Network Interface Instances. network_interfaces[0] will be picked as the primary network and bound to public ip or load balancers.
    # @return [Hash]
    #
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesets/createorupdate
    #
    def create_vmss(resource_group_name, vm_params, network_interfaces)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vm_params[:vmss_name])
      os_profile = {}
      case vm_params[:os_type]
      when 'linux'
        os_profile['computerNamePrefix'] = vm_params[:vmss_name]
        os_profile['adminUsername'] = vm_params[:ssh_username]
        os_profile['linuxConfiguration'] = {
          'disablePasswordAuthentication' => 'true',
          'ssh' => {
            'publicKeys' => [
              {
                'path'    => "/home/#{vm_params[:ssh_username]}/.ssh/authorized_keys",
                'keyData' => vm_params[:ssh_cert_data]
              }
            ]
          }
        }
      when 'windows'
        # TODO: add support for the windows.
        raise ArgumentError, "Unsupported os type: #{vm_params[:os_type]}"
      else
        raise ArgumentError, "Unsupported os type: #{vm_params[:os_type]}"
      end

      network_profile = {
        'networkInterfaceConfigurations' => []
      }
      network_interfaces.each_with_index do |network, index|
        nic = {
          'name' => "nic-#{index}",
          'properties' => {
            'primary' => index.zero?,
            'enableIPForwarding' => true,
            'ipConfigurations' => [
              {
                'name' => "ipconfig#{index}",
                'properties' => {
                  'subnet' => {
                    'id' => network[:subnet][:id]
                  },
                  'loadBalancerInboundNatPools' => [],
                  'loadBalancerBackendAddressPools' => []
                }
              }
            ]
          }
        }
        unless vm_params[:load_balancer].nil?
          nic['properties']['ipConfigurations'][0]['properties']['loadBalancerBackendAddressPools'].push(
            'id' => vm_params[:load_balancer][:backend_address_pools][0][:id]
          )
        end

        unless network[:network_security_group].nil?
          nic['properties']['networkSecurityGroup'] = {
            'id' => network[:network_security_group][:id]
          }
        end
        network_profile['networkInterfaceConfigurations'].push(nic)
      end

      os_disk = {
        'createOption' => 'FromImage',
        'caching'      => vm_params[:os_disk][:disk_caching],
        # Comment this out, use the default in the image,
        # will handle this when resolving https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/533
        # 'managedDisk' => {
        #   'storageAccountType' => 'Standard_LRS'
        # }
      }
      os_disk['diskSizeGB'] = vm_params[:os_disk][:disk_size] unless vm_params[:os_disk][:disk_size].nil?
      data_disks = []
      unless vm_params[:ephemeral_disk].nil?
        data_disks.push(
          'createOption' => 'Empty',
          'diskSizeGB'   => vm_params[:ephemeral_disk][:disk_size],
          'lun'          => EPHEMERAL_DISK_LUN
        )
      end
      storage_profile = {
        'imageReference' => {
          'id' => vm_params[:image_id]
        },
        'osDisk' => os_disk,
        'dataDisks' => data_disks
      }

      vmss = {
        'sku' => {
          'tier' => 'Standard',
          'capacity' => vm_params[:initial_capacity],
          'name' => vm_params[:instance_type]
        },
        'location' => vm_params[:location],
        'properties' => {
          'overprovision' => false,
          'virtualMachineProfile' => {
            'storageProfile' => storage_profile,
            'osProfile' => os_profile,
            'networkProfile' => network_profile
          },
          'upgradePolicy' => {
            'mode' => 'Manual'
          }
        },
        'zones' => vm_params[:availability_zones]
      }

      params = {
        'validating' => 'true'
      }
      http_put(url, vmss, params)
    end

    # Will call the update api of the vmss
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesets/createorupdate
    def scale_vmss_up(resource_group_name, vmss_name, number)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      vmss = _get_vmss_by_name(resource_group_name, vmss_name)
      vmss['sku']['capacity'] = vmss['sku']['capacity'].to_i + number
      params = {
        'validating' => 'true'
      }
      http_put(url, vmss, params)
    end
    # VMSS related ends

    # Instances related starts

    # List the instances in the vmss.
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/list
    def get_vmss_instances(resource_group_name, vmss_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name, others: 'virtualMachines')
      result = get_resource_by_id(url)
      vmss_instances = nil
      unless result.nil?
        vmss_instances = []
        result['value'].each do |instance|
          vmss_instances.push(
            instanceId: instance['instanceId'],
            name: instance['name'],
            zones: instance['zones']
          )
        end
      end
      vmss_instances
    end

    # Get information of the one instance in the vmss.
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/get
    def get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      vmss_instance = nil
      result = _get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      unless result.nil?
        vmss_instance = {}
        vmss_instance[:id]          = result['id']
        vmss_instance[:name]        = result['name']
        vmss_instance[:location]    = result['location']
        vmss_instance[:sku]         = {}
        vmss_instance[:sku][:name]  = result['sku']['name']
        vmss_instance[:zones]       = result['zones']
        vmss_instance[:tags]        = result['tags']
        properties = result['properties']
        vmss_instance[:provisioning_state] = properties['provisioningState']
        storage_profile = properties['storageProfile']
        os_disk = storage_profile['osDisk']
        vmss_instance[:os_disk] = {}
        vmss_instance[:os_disk][:name]    = os_disk['name']
        vmss_instance[:os_disk][:caching] = os_disk['caching']
        vmss_instance[:os_disk][:size]    = os_disk['diskSizeGb']

        vmss_instance[:os_disk][:uri]     = os_disk['vhd']['uri'] if os_disk.key?('vhd')
        if os_disk.key?('managedDisk')
          vmss_instance[:os_disk][:managed_disk] = {}
          vmss_instance[:os_disk][:managed_disk][:id]                   = os_disk['managedDisk']['id']
          vmss_instance[:os_disk][:managed_disk][:storage_account_type] = os_disk['managedDisk']['storageAccountType']
        end

        vmss_instance[:data_disks] = []
        storage_profile['dataDisks'].each do |data_disk|
          disk = {}
          disk[:name]    = data_disk['name']
          disk[:lun]     = data_disk['lun']
          disk[:caching] = data_disk['caching']
          disk[:size]    = data_disk['diskSizeGb']

          disk[:uri]     = data_disk['vhd']['uri'] if data_disk.key?('vhd')
          if data_disk.key?('managedDisk')
            disk[:managed_disk] = {}
            disk[:managed_disk][:id]                   = data_disk['managedDisk']['id']
            disk[:managed_disk][:storage_account_type] = data_disk['managedDisk']['storageAccountType']
          end

          # TODO: handle this.
          # disk[:disk_bosh_id] = result['tags'].fetch("#{DISK_ID_TAG_PREFIX}-#{data_disk['name']}", data_disk['name'])
          vmss_instance[:data_disks].push(disk)
        end
        vmss_instance[:network_interfaces] = []
        properties['networkProfile']['networkInterfaces'].each do |nic_properties|
          vmss_instance[:network_interfaces].push(get_network_interface(nic_properties['id']))
        end

        boot_diagnostics = properties.fetch('diagnosticsProfile', {}).fetch('bootDiagnostics', {})
        vmss_instance[:diag_storage_uri] = boot_diagnostics['storageUri'] if boot_diagnostics['enabled']
      end
      vmss_instance
    end

    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vmss_name  - Name of the vmss.
    # @param [String] vmss_instance_id  - Id of the instance.
    # @param [Hash] vm_params  - parameters for creating the disk.
    # @return [String] lun of the created disk.
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/update
    def attach_disk_to_vmss_instance(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      vmss_instance = _get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      lun = _get_next_available_lun(
        vmss_instance['sku']['name'],
        vmss_instance['properties']['storageProfile']['dataDisks']
      )

      raise AzureError, "attach_disk_to_virtual_machine_instance - cannot find an available lun in the virtual machine '#{vmss_name}' '#{vmss_instance_id}' for the new disk '#{disk_params[:disk_id]}'" if lun.nil?

      caching = disk_params[:caching]
      vmss_instance['properties']['storageProfile']['dataDisks'].push(
        'lun' => lun,
        'createOption' => 'Attach',
        'caching' => caching,
        'managedDisk' => {
          'id' => disk_params[:disk_id]
        }
      )
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}"
      params = {
        'validating' => 'true'
      }
      http_put(url, vmss_instance, params)
      lun
    end

    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vmss_name  - Name of the vmss.
    # @param [String] vmss_instance_id  - Id of the instance.
    # @param [String] disk_id  - id of the disk to be detached.
    # @return [Boolean]
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/update
    def detach_disk_from_vmss_instance(resource_group_name, vmss_name, vmss_instance_id, disk_id)
      vmss_instance = _get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      found = false
      vmss_instance['properties']['storageProfile']['dataDisks'].delete_if do |i|
        result = i['managedDisk']['id'] == disk_id
        found = true if result
        found
      end
      raise Bosh::Clouds::CloudError, "disk id: #{disk_id} not found in vmss: #{vmss_name} instance_id: #{vmss_instance_id}." unless found

      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}"
      params = {
        'validating' => 'true'
      }
      http_put(url, vmss_instance, params)
    end

    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vmss_name  - Name of the vmss.
    # @param [String] vmss_instance_id  - Id of the instance.
    # @return [Boolean]
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/restart
    def reboot_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}/restart"
      params = {
        'validating' => 'true'
      }
      http_post(url, nil, params)
    end

    # @param [String] resource_group_name  - Name of resource group.
    # @param [String] vmss_name  - Name of the vmss.
    # @param [String] vmss_instance_id  - Id of the instance.
    # @return [Boolean]
    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/delete
    def delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}"
      params = {
        'validating' => 'true'
      }
      http_delete(url, params)
    end

    # @See https://docs.microsoft.com/en-us/rest/api/compute/virtualmachinescalesetvms/update
    def set_vmss_instance_metadata(resource_group_name, vmss_name, vmss_instance_id, tags)
      vmss_instance = _get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}"
      if !vmss_instance['tags'].nil?
        vmss_instance['tags'].merge!(tags)
      else
        vmss_instance['tags'] = tags
      end
      params = {
        'validating' => 'true'
      }
      http_put(url, vmss_instance, params)
    end
    # Instances related ends

    private

    def _get_vmss_by_name(resource_group_name, vmss_name)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      result = get_resource_by_id(url)
      @logger.info("_get_vmss_by_name result is: #{result}")
      result
    end

    def _get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      url = rest_api_url(REST_API_PROVIDER_COMPUTE, REST_API_VIRTUAL_MACHINE_SCALE_SETS, resource_group_name: resource_group_name, name: vmss_name)
      url += "/virtualMachines/#{vmss_instance_id}"
      result = get_resource_by_id(url)
      @logger.info("_get_vmss_instance result is: #{result}")
      result
    end
  end
end
