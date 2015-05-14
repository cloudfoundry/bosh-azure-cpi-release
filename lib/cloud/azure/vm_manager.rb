module Bosh::AzureCloud
  class VMManager
    include Helpers

    def initialize(storage_account_name, registry, disk_manager)
      @storage_account_name = storage_account_name
      @registry = registry
      @disk_manager = disk_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def create(uuid, stemcell_uri, cloud_opts, network_configurator, resource_pool)
      instance_id = generate_instance_id(cloud_opts["resource_group_name"], uuid)

      if @location.nil?
        location_opts = [
                "-t",
                "get",
                "-r",
                cloud_opts['resource_group_name'],
                @storage_account_name,
                "Microsoft.Storage/storageAccounts"
              ]
        @location = JSON(invoke_azure_js(location_opts))["location"]
      end

      params = {
        :vmName              => instance_id,
        :nicName             => instance_id,
        :adminUserName       => cloud_opts['ssh_user'],
        :imageUri            => stemcell_uri,
        :osvhdUri            => @disk_manager.get_new_os_disk_uri(instance_id),
        :location            => @location,
        :vmSize              => resource_pool['instance_type'],
        :storageAccountName  => @storage_account_name,
        :customData          => get_user_data(instance_id, network_configurator.dns),
        :sshKeyData          => File.read(cloud_opts['ssh_certificate_file'])
      }
      params[:virtualNetworkName] = network_configurator.virtual_network_name
      params[:subnetName]         = network_configurator.subnet_name

      unless network_configurator.private_ip.nil?
        params[:privateIPAddress]     = network_configurator.private_ip
        params[:privateIPAddressType] = "Static"
      end

      args = ["-t", "deploy", "-r", cloud_opts['resource_group_name']]
      args.push(File.join(File.dirname(__FILE__),"azure_crp","azure_vm.json"))
      args.push(Base64.encode64(params.to_json()))

      result = invoke_azure_js(args, true)

      unless network_configurator.vip_network.nil?
        ip_crp_template = 'azure_vm_endpoints.json'
        args = [
                "-r",
                cloud_opts['resource_group_name'],
                "-t",
                "findResource",
                "properties:ipAddress",
                network_configurator.reserved_ip,
                "Microsoft.Network/publicIPAddresses"
              ]
        ipname = invoke_azure_js(args, true)

        #if vip is not a reserved ip, then create an ipaddress with given label name
        if ipname.nil? || ipname.empty?
          ip_crp_template = "azure_vm_ip.json"
          @logger.debug("#{network_configurator.reserved_ip} is not a reserved ip , go to create ip and take it as fqdn name")
          ipname = instance_id
          args = [
                  "-r",
                  cloud_opts['resource_group_name'],
                  "-t",
                  "createip",
                  ipname,
                  instance_id
                 ]
          result = invoke_azure_js(args, true)
        end

        #bind the ip or endpoint to nic of that vm
        p = {
          "storageAccountName"      => @storage_account_name,
          "lbName"                  => instance_id,
          "publicIPAddressName"     => ipname,
          "nicName"                 => instance_id,
          "virtualNetworkName"      => "vnet"
        }
        p["TcpEndPoints"] = network_configurator.tcp_endpoints unless network_configurator.tcp_endpoints.empty?
        p["UdpEndPoints"] = network_configurator.udp_endpoints unless network_configurator.udp_endpoints.empty?

        p = p.merge(params)
        args = ["-t", "deploy", "-r", cloud_opts["resource_group_name"]]
        args.push(File.join(File.dirname(__FILE__), "azure_crp", ip_crp_template))
        args.push(Base64.encode64(p.to_json()))
        result = invoke_azure_js(args, true)
      end

      instance_id
    rescue => e
      delete(instance_id)
      cloud_error("create vm failed: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def find(instance_id)
      instance = nil

      begin
        ret = invoke_azure_js_with_id(["get", instance_id, "Microsoft.Compute/virtualMachines"])
        unless ret.nil?
          vm = JSON(ret)
          publicip = invoke_azure_js_with_id(["get", instance_id, "Microsoft.Network/publicIPAddresses", '--silence'])
          publicip = JSON(publicip) unless publicip.nil?
          dipaddress = publicip.nil? ? nil : publicip["properties"]["ipAddress"]
          data_disks = []
          vm["properties"]["storageProfile"]["dataDisks"].each do |disk|
            data_disks << {
              "name" => disk["name"],
              "lun"  => disk["lun"],
              "uri"  => disk["vhd"]["uri"]
            }
          end

          nic = JSON(invoke_azure_js_with_id(["get", instance_id, "Microsoft.Network/networkInterfaces"]))["properties"]["ipConfigurations"][0]
          instance = {
            "data_disks"    => data_disks,
            "ipaddress"     => nic["properties"]["privateIPAddress"],
            "vm_name"       => vm["name"],
            "dipaddress"    => dipaddress,
            "status"        => vm["properties"]["provisioningState"]
          }
        end
      rescue => e
        @logger.debug("Cannot find instance by id #{instance_id}: #{e.message}  #{e.backtrace.join("\n")} ")
      end

      instance
    end

    def delete(instance_id)
      @logger.info("delete(#{instance_id})")

      disks = []
      begin
        disks = get_disks(instance_id)
      rescue => e
        @logger.warn("Cannot get data disks for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end
      disks << get_os_disk_name(instance_id)

      begin
        invoke_azure_js_with_id(["delete", instance_id, "Microsoft.Compute/virtualMachines"])
      rescue => e
        @logger.warn("Cannot delete VM instance for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end

      begin
        invoke_azure_js_with_id(["delete", instance_id, "Microsoft.Network/loadBalancers"])
      rescue => e
        @logger.warn("Cannot delete load balancer for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end

      begin
        invoke_azure_js_with_id(["delete", instance_id, "Microsoft.Network/networkInterfaces"])
      rescue => e
        @logger.warn("Cannot network interfaces for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end

      begin
        invoke_azure_js_with_id(["delete", instance_id, "Microsoft.Network/publicIPAddresses"])
      rescue => e
        @logger.warn("Cannot delete public IP address for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
      end

      disks.each do |disk|
        begin
          @disk_manager.delete_disk(disk)
        rescue => e
          @logger.warn("Cannot delete disk #{disk} for #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
        end
      end
    end

    def reboot(instance_id)
      @logger.info("reboot(#{instance_id})")
      invoke_azure_js_with_id(["restart", instance_id])
    rescue => e
      @logger.warn("Cannot reboot #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def start(instance_id)
      @logger.info("start(#{instance_id})")
      invoke_azure_js_with_id(["start", instance_id])
    rescue => e
      @logger.warn("Cannot start #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def shutdown(instance_id)
      @logger.info("shutdown(#{instance_id})")
      invoke_azure_js_with_id(["stop", instance_id])
    rescue => e
      @logger.warn("Cannot shutdown #{instance_id}: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def set_metadata(instance_id, metadata)
      @logger.info("set_metadata(#{instance_id}, #{metadata})")
      tag = ""
      metadata.each_pair { |key, value| tag << "#{key}=#{value};" }
      invoke_azure_js_with_id(["setTag", instance_id, "Microsoft.Compute/virtualMachines", tag[0..-2]])
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
      invoke_azure_js_with_id(["adddisk", instance_id, disk_uri])
      get_volume_name(instance_id, disk_name)
    end

    def detach_disk(instance_id, disk_name)
      @logger.info("detach_disk(#{instance_id}, #{disk_name})")
      disk_uri= @disk_manager.get_disk_uri(disk_name)
      invoke_azure_js_with_id(["rmdisk", instance_id, disk_uri])
    end

    def get_disks(instance_id)
      @logger.info("get_disks(#{instance_id})")
      vm = find(instance_id) || cloud_error('Given instance id does not exist')
      data_disks = []
      vm['data_disks'].each do |disk|
        data_disks << disk['name']
      end
      data_disks
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry.endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(Yajl::Encoder.encode(user_data))
    end

    def get_volume_name(instance_id, disk_name)
      data_disk = find(instance_id)["data_disks"].find { |disk| disk["name"] == disk_name}
      data_disk || cloud_error('Given disk name is not attached to given instance id')
      lun = get_disk_lun(data_disk)
      @logger.info("get_volume_name return lun #{lun}")
      "/dev/sd#{('c'.ord + lun).chr}"
    end

    def get_disk_lun(data_disk)
      data_disk["lun"] != "" ? data_disk["lun"].to_i : 0
    end

  end
end
