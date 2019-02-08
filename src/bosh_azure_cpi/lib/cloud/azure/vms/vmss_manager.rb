# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSManager < VMManagerBase
    def initialize(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager, config_disk_manager)
      super(azure_config.use_managed_disks, azure_client, stemcell_manager, stemcell_manager2, light_stemcell_manager)

      @azure_config = azure_config
      @keep_failed_vms = @azure_config.keep_failed_vms
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @disk_manager2 = disk_manager2
      @azure_client = azure_client
      @storage_account_manager = storage_account_manager
      @stemcell_manager = stemcell_manager
      @stemcell_manager2 = stemcell_manager2
      @light_stemcell_manager = light_stemcell_manager
      @use_managed_disks = azure_config.use_managed_disks
      @config_disk_manager = config_disk_manager
    end

    def create(bosh_vm_meta, vm_props, network_configurator, env)
      # steps:
      # 1. get or create the vmss.
      # 2. scale the vmss one node up or create it.
      # 3. prepare one config disk and then attach it.
      CPILogger.instance.logger.info("vmss_create(#{bosh_vm_meta}, #{vm_props}, ..., ...)")
      resource_group_name = vm_props.resource_group_name
      vmss_name = _get_vmss_name(vm_props, env)
      _ensure_resource_group_exists(resource_group_name, vm_props.location)

      stemcell_info = _get_stemcell_info(bosh_vm_meta.stemcell_cid, vm_props, nil)
      vmss_instance_id = nil # this is the instance id like '1', '2', concept in vmss.
      vmss_params = {
        resource_group_name: resource_group_name,
        availability_zones: vm_props.vmss.availability_zones,
        vmss_name: vmss_name,
        location: vm_props.location,
        instance_type: vm_props.instance_type
      }
      vmss_params[:image_id] = stemcell_info.uri
      vmss_params[:os_type] = stemcell_info.os_type

      raise ArgumentError, "Unsupported os type: #{vmss_params[:os_type]}" if stemcell_info.os_type != 'linux'

      vmss_params[:ssh_username]  = @azure_config.ssh_user
      vmss_params[:ssh_cert_data] = @azure_config.ssh_public_key
      # there's extra name field in os_disk and ephemeral_disk, will ignore it when creating vmss.
      vmss_params[:os_disk], vmss_params[:ephemeral_disk] = _build_vmss_disks(vmss_name, stemcell_info, vm_props)

      network_interfaces = []
      networks = network_configurator.networks
      networks.each_with_index do |network, _|
        subnet = _get_network_subnet(network)
        network_security_group = _get_network_security_group(vm_props, network)
        network_interfaces.push(subnet: subnet, network_security_group: network_security_group)
      end
      # TODO: handle the application gateway, public ip too.
      unless vm_props.load_balancer.name.nil?
        load_balancer = @azure_client.get_load_balancer_by_name(vm_props.load_balancer.resource_group_name, vm_props.load_balancer.name)
        vmss_params[:load_balancer] = load_balancer
      end
      batching_request = {
        grouping_key: vmss_name,
        params: vmss_params
      }
      executor = lambda do |request, count|
        CPILogger.instance.logger.info("executing with request:#{request.to_json}, count: #{count}")
        rg_name = request[:resource_group_name]
        existing_vmss = @azure_client.get_vmss_by_name(rg_name, vmss_name)
        request[:capacity] = if existing_vmss.nil?
                               1
                             else
                               existing_vmss[:sku][:capacity].to_i + count
                             end
        existing_instances = @azure_client.get_vmss_instances(rg_name, vmss_name)
        @azure_client.create_or_update_vmss(request, network_interfaces)
        updated_instances = @azure_client.get_vmss_instances(rg_name, vmss_name)
        return _get_newly_created_instance(existing_instances, updated_instances)
      end
      instance = Bosh::AzureCloud::Batching.instance.execute(batching_request, executor)
      CPILogger.instance.logger.info("got instance #{JSON.dump(instance)}")
      vmss_instance_id = instance[:instanceId]
      vm_name = instance[:name]
      instance_id = _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
      meta_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_meta_data_obj(
        instance_id.to_s,
        @azure_config.ssh_public_key
      )

      vmss_params[:name] = vm_name
      user_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_user_data_obj(@registry_endpoint, instance_id.to_s, network_configurator.default_dns, vmss_params)

      # TODO merge things going into agent settings

      config_disk_id, = @config_disk_manager.prepare_config_disk(
        resource_group_name,
        vm_name,
        vm_props.location,
        instance[:zones].nil? ? nil : instance[:zones][0],
        meta_data_obj,
        user_data_obj
      )

      disk_params = _get_disk_params(config_disk_id, instance_id.use_managed_disks?)

      _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)

      [instance_id, vmss_params]
    rescue StandardError => e
      error_message = nil
      if !vmss_instance_id.nil?
        error_message = 'New instance in VMSS created, but probably config disk failed to attach.'
        error_message += "\t Resource Group: #{resource_group_name}\n"
        error_message += "\t Virtual Machine Scale Set: #{vmss_name}\n"
        error_message += "\t Instance Id: #{vmss_instance_id}\n"
      else
        error_message = 'Instance not created.'
      end
      if @keep_failed_vms
        error_message += 'You need to delete the vm instance created after finishing investigation.\n'
      else
        @azure_client.delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id) unless vmss_instance_id.nil?
      end
      raise Bosh::Clouds::VMCreationFailed.new(false), "#{error_message}\n#{e.backtrace.join("\n")}"
    end

    def find(instance_id)
      CPILogger.instance.logger.info("vmss_find(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.get_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def delete(instance_id)
      CPILogger.instance.logger.info("vmss_delete(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      vmss_instance = @azure_client.get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      @azure_client.delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id) if vmss_instance

      vmss_instance[:data_disks]&.each do |data_disk|
        if @config_disk_manager.config_disk?(data_disk[:name])
          CPILogger.instance.logger.info("deleting disk: #{data_disk[:managed_disk][:id]}")
          @disk_manager2.delete_disk(data_disk[:managed_disk][:resource_group_name], data_disk[:name])
          CPILogger.instance.logger.info("deleted disk: #{data_disk[:managed_disk][:id]}")
        end
      end
    end

    def reboot(instance_id)
      CPILogger.instance.logger.info("vmss_reboot(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.reboot_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def set_metadata(instance_id, metadata)
      CPILogger.instance.logger.info("vmss_set_metadata(#{instance_id}, #{metadata})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.set_vmss_instance_metadata(
        resource_group_name,
        vmss_name,
        instance_id,
        metadata.merge(AZURE_TAGS)
      )
    end

    def attach_disk(instance_id, disk_id)
      CPILogger.instance.logger.info("vmss_attach_disk(#{instance_id}, #{disk_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      disk_params = _get_disk_params(disk_id, instance_id.use_managed_disks?)
      lun = _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      raise Bosh::Clouds::CloudError, "Failed to attach disk: #{disk_id} to #{instance_id}." if lun.nil?

      lun.to_s
    end

    def detach_disk(instance_id, disk_id)
      CPILogger.instance.logger.info("vmss_detach_disk(#{instance_id}, #{disk_id})")
      @azure_client.detach_disk_from_vmss_instance(
        instance_id.resource_group_name,
        instance_id.vmss_name,
        instance_id.vmss_instance_id,
        disk_id.disk_name
      )
    end

    private

    def _build_vmss_disks(vmss_name, stemcell_info, vm_props)
      # TODO: add support for the unmanaged disk.
      os_disk = @disk_manager2.os_disk(vmss_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
      ephemeral_disk = @disk_manager2.ephemeral_disk(vmss_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
      [os_disk, ephemeral_disk]
    end

    # returns instance_id, name, zones list
    def _get_newly_created_instance(old, newly)
      old_instance_ids = old.map { |row| row[:instanceId] }
      new_instance_ids = newly.map { |row| row[:instanceId] }
      created_instance_ids = new_instance_ids - old_instance_ids
      CPILogger.instance.logger.info("old_instance_ids: #{old_instance_ids} new_instance_ids #{new_instance_ids}")
      # raise Bosh::Clouds::CloudError, 'more instance found.' if created_instance_ids.length != 1
      created_instances = []
      created_instance_ids.each do |instance_id|
        instance = newly.find { |i| i[:instanceId] == instance_id }
        created_instances.push(instance)
      end
      created_instances
    end

    def _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
      # TODO: add support for the unmanaged disk.
      instance_id = VMSSInstanceId.create(vm_props.resource_group_name, bosh_vm_meta.agent_id, vmss_name, vmss_instance_id)
      instance_id
    end

    def _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      CPILogger.instance.logger.info("attaching disk #{disk_params[:disk_id]} to #{resource_group_name} #{vmss_name} #{vmss_instance_id}")
      @azure_client.attach_disk_to_vmss_instance(resource_group_name, vmss_name, vmss_instance_id, disk_params)
    end

    def _get_vmss_name(vm_props, env)
      # use the bosh group as the vmss name.
      # this would be published, tracking issue here: https://github.com/cloudfoundry/bosh/issues/2034

      vm_props.vmss.name if !vm_props.vmss.nil? && !vm_props.vmss.name.nil?

      bosh_group_exists = env.nil? || env['bosh'].nil? || env['bosh']['group'].nil?
      if !bosh_group_exists
        vmss_name = env['bosh']['group']
        # max windows vmss name length 15
        # max linux vmss name length 63
        if vmss_name.size > 63
          md = Digest::MD5.hexdigest(vmss_name) # 32
          vmss_name = "vmss-#{md}-#{vmss_name[-31..-1]}"
        end
        vmss_name
      else
        cloud_error('currently the bosh group should be there, later will add the support without the group.')
      end
    end
  end
end
