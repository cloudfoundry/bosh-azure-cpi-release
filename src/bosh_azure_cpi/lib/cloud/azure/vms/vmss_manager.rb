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
      @logger = Bosh::Clouds::Config.logger
    end

    def create(bosh_vm_meta, location, vm_props, network_configurator, env)
      # steps:
      # 1. get or create the vmss.
      # 2. scale the vmss one node up or create it.
      # 3. prepare one config disk and then attach it.
      @logger.info("vmss_create(#{bosh_vm_meta}, #{location}, #{vm_props}, ..., ...)")
      resource_group_name = vm_props.resource_group_name
      vmss_name = _get_vmss_name(env)
      _ensure_resource_group_exists(resource_group_name, location)

      existing_vmss = @azure_client.get_vmss_by_name(resource_group_name, vmss_name)
      vmss_params = {}
      instance_id = _build_instance_id(bosh_vm_meta, vm_props, vmss_name, nil)
      stemcell_info = _get_stemcell_info(bosh_vm_meta.stemcell_id, vm_props, location)
      vmss_instance_id = nil
      vm_name = nil
      if existing_vmss.nil?
        vmss_params = {
          vmss_name: vmss_name,
          location: location,
          instance_type: vm_props.instance_type
        }
        vmss_params[:image_id] = stemcell_info.uri
        vmss_params[:os_type] = stemcell_info.os_type

        raise ArgumentError, "Unsupported os type: #{vmss_params[:os_type]}" if stemcell_info.os_type != 'linux'

        vmss_params[:ssh_username]  = @azure_config.ssh_user
        vmss_params[:ssh_cert_data] = @azure_config.ssh_public_key
        # there's extra name field in os_disk and ephemeral_disk, will ignore it when creating vmss.
        vmss_params[:os_disk], vmss_params[:ephemeral_disk] = _build_vmss_disks(instance_id, stemcell_info, vm_props)
        network_interfaces = []
        vmss_params[:initial_capacity] = 1
        networks = network_configurator.networks
        networks.each_with_index do |network, _|
          subnet = _get_network_subnet(network)
          network_security_group = _get_network_security_group(vm_props, network)
          network_interfaces.push(subnet: subnet, network_security_group: network_security_group)
        end
        # TODO: handle the application gateway, public ip too.
        unless vm_props.load_balancer.nil?
          load_balancer = @azure_client.get_load_balancer_by_name(vm_props.load_balancer)
          vmss_params[:load_balancer] = load_balancer
        end
        flock(vmss_name.to_s, File::LOCK_EX) do
          @azure_client.create_vmss(resource_group_name, vmss_params, network_interfaces)
          vmss_instances_result = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
          vmss_instance_id = vmss_instances_result[0][:instanceId]
          vm_name = vmss_instances_result[0][:name]
        end
      else
        vmss_params[:os_disk], vmss_params[:ephemeral_disk] = _build_vmss_disks(instance_id, stemcell_info, vm_props)
        # TODO: create one task to batch the scale up.
        flock(vmss_name.to_s, File::LOCK_EX) do
          existing_instances = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
          @azure_client.scale_vmss_up(resource_group_name, vmss_name, 1)
          updated_instances = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
          vmss_instance_id, vm_name = _get_newly_created_instance(existing_instances, updated_instances)
        end
      end
      instance_id = _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
      meta_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_meta_data_obj(
        instance_id.to_s,
        @azure_config.ssh_public_key
      )

      vmss_params[:name] = vm_name
      user_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_user_data_obj(@registry_endpoint, instance_id.to_s, network_configurator.default_dns)

      config_disk_id, = @config_disk_manager.prepare_config_disk(
        resource_group_name,
        vm_name,
        location,
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
      @logger.info("vmss_find(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.get_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def delete(instance_id)
      @logger.info("vmss_delete(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      vmss_instance = @azure_client.get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      @azure_client.delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id) if vmss_instance
    end

    def reboot(instance_id)
      @logger.info("vmss_reboot(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.reboot_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def set_metadata(instance_id, metadata)
      @logger.info("vmss_set_metadata(#{instance_id}, #{metadata})")
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
      @logger.info("vmss_attach_disk(#{instance_id}, #{disk_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      disk_params = _get_disk_params(disk_id, instance_id.use_managed_disks?)
      _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
    end

    def detach_disk(instance_id, disk_id)
      @logger.info("vmss_detach_disk(#{instance_id}, #{disk_id})")
      @azure_client.detach_disk_from_vmss_instance(
        instance_id.resource_group_name,
        instance_id.vmss_name,
        instance_id.vmss_instance_id,
        disk_id
      )
    end

    private

    def _build_vmss_disks(instance_id, stemcell_info, vm_props)
      # TODO: add support for the unmanaged disk.
      os_disk = @disk_manager2.os_disk(instance_id.vmss_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
      ephemeral_disk = @disk_manager2.ephemeral_disk(instance_id.vmss_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.use_root_disk)
      [os_disk, ephemeral_disk]
    end

    # returns instance_id, name
    def _get_newly_created_instance(old, newly)
      old_instance_ids = old.map { |row| row[:instanceId] }
      new_instance_ids = newly.map { |row| row[:instanceId] }
      created_instance_ids = new_instance_ids - old_instance_ids
      @logger.info("old_instance_ids: #{old_instance_ids} new_instance_ids #{new_instance_ids}")
      raise Bosh::Clouds::CloudError, 'more instance found.' if created_instance_ids.length != 1

      insatnce_id = created_instance_ids[0]
      instance = newly.find { |i| i[:instanceId] == insatnce_id }
      [instance[:instanceId], instance[:name]]
    end

    def _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
      # TODO: add support for the unmanaged disk.
      instance_id = VMSSInstanceId.create(vm_props.resource_group_name, bosh_vm_meta.agent_id, vmss_name, vmss_instance_id)
      instance_id
    end

    def _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      @logger.info("attaching disk #{disk_params[:disk_id]} to #{resource_group_name} #{vmss_name} #{vmss_instance_id}")
      @azure_client.attach_disk_to_vmss_instance(resource_group_name, vmss_name, vmss_instance_id, disk_params)
    end

    def _get_vmss_name(env)
      # use the bosh group as the vmss name.
      # this would be published, tracking issue here: https://github.com/cloudfoundry/bosh/issues/2034
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
