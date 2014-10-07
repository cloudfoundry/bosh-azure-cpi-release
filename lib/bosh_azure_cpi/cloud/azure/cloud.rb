require 'azure'
require 'xmlsimple'

require_relative 'stemcell_finder'
require_relative 'vm_manager'
require_relative 'affinity_group_manager'
require_relative 'virtual_network_manager'
require_relative 'stemcell_manager'
require_relative 'storage_account_manager'
require_relative 'blob_manager'
require_relative 'helpers'

module Bosh::AzureCloud
  class Cloud < Bosh::Cloud
    attr_accessor :options

    include Helpers

    ##
    # Cloud initialization
    #
    # @param [Hash] options cloud options
    def initialize(options)
      @options = options.dup.freeze
      validate_options

      @vmm_endpoint_url = 'https://management.core.windows.net'
      @seed_api_cert_path = File.absolute_path("#{ENV['HOME']}/api-cert.pem")

      # Logger is available as a public method, but bosh::Clouds::Config is apparently nil. Need to investigate
      #@logger = bosh::Clouds::Config.logger
      @metadata_lock = Mutex.new

      init_azure

      # TODO: This is executed before storage manager can check for existence of the named storage account in manifest
      # TODO: Currently getting an Azure::Core::Http::HTTPError with a 403 for some reason... Need to figure out why
      prepare_azure_cert
    end

    ##
    # Get the vm_id of this host
    #
    # @return [String] opaque id later used by other methods of the CPI
    def current_vm_id
      @metadata_lock.synchronize do
        instance_manager.instance_id
      end
    end

    ##
    # Creates a stemcell
    #
    # @param [String] image_path path to an opaque blob containing the stemcell image
    # @param [Hash] cloud_properties properties required for creating this template
    #               specific to a CPI
    # @return [String] opaque id later used by {#create_vm} and {#delete_stemcell}
    def create_stemcell(image_path, cloud_properties)
      vm = current_vm_id
      # NOTE: May need to use the deployment name from the virtual machine object
      deployment_name = cloud_service_service.get_cloud_service_properties(vm_from_yaml(vm)[:cloud_service_name]).deployment_name

      `yes y | sudo -n waagent -deprovision`
      raise if !$?.success?

      instance_manager.shutdown(vm)

      stemcell_id = stemcell_manager.imageize_vhd(vm, deployment_name)

      # TODO: Figure a way to 'reprovision' with waagent so we can restart the instance
      instance_manager.start(vm)

      stemcell_id
    end

    ##
    # Deletes a stemcell
    #
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @return [void]
    def delete_stemcell(stemcell_id)
      stemcell_manager.delete_image(stemcell_id)
    end

    ##
    # Creates a VM - creates (and powers on) a VM from a stemcell with the proper resources
    # and on the specified network. When disk locality is present the VM will be placed near
    # the provided disk so it won't have to move when the disk is attached later.
    #
    # Sample networking config:
    #  {"network_a" =>
    #    {
    #      "netmask"          => "255.255.248.0",
    #      "ip"               => "172.30.41.40",
    #      "gateway"          => "172.30.40.1",
    #      "dns"              => ["172.30.22.153", "172.30.22.154"],
    #      "cloud_properties" => {"name" => "VLAN444"}
    #    }
    #  }
    #
    # Sample resource pool config (CPI specific):
    #  {
    #    "ram"  => 512,
    #    "disk" => 512,
    #    "cpu"  => 1
    #  }
    # or similar for EC2:
    #  {"name" => "m1.small"}
    #
    # @param [String] agent_id UUID for the agent that will be used later on by the director
    #                 to locate and talk to the agent
    # @param [String] stemcell_id stemcell id that was once returned by {#create_stemcell}
    # @param [Hash] resource_pool cloud specific properties describing the resources needed
    #               for this VM
    # @param [Hash] networks list of networks and their settings needed for this VM
    # @param [optional, String, Array] disk_locality disk id(s) if known of the disk(s) that will be
    #                                    attached to this vm
    # @param [optional, Hash] env environment that will be passed to this vm
    # @return [String] opaque id later used by {#configure_networks}, {#attach_disk},
    #                  {#detach_disk}, and {#delete_vm}
    def create_vm(agent_id, stemcell_id, resource_pool, networks, disk_locality = nil, env = nil)
      raise if not(stemcell_finder.exist?(stemcell_id))
      vnet_manager.create(networks)
      instance = instance_manager.create(agent_id, stemcell_id, azure_properties.merge({'user' => 'bosh'}))

      # convert instance to a yaml string containing a hash of vm_name and cloud_service_name (both are needed for lookup)
      vm_to_yaml(instance)
    end

    ##
    # Deletes a VM
    #
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @return [void]
    def delete_vm(vm_id)
      instance_manager.delete(vm_id)
    end

    ##
    # Checks if a VM exists
    #
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @return [Boolean] True if the vm exists
    def has_vm?(vm_id)
      !instance_manager.find(vm_id).nil?
    end

    ##
    # Reboots a VM
    #
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @param [Optional, Hash] CPI specific options (e.g hard/soft reboot)
    # @return [void]
    def reboot_vm(vm_id)
      instance_manager.reboot(vm_id)
    end

    ##
    # Set metadata for a VM
    #
    # Optional. Implement to provide more information for the IaaS.
    #
    # @param [String] vm vm id that was once returned by {#create_vm}
    # @param [Hash] metadata metadata key/value pairs
    # @return [void]
    def set_vm_metadata(vm, metadata)
    end

    ##
    # Configures networking an existing VM.
    #
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @param [Hash] networks list of networks and their settings needed for this VM,
    #               same as the networks argument in {#create_vm}
    # @return [void]
    def configure_networks(vm_id, networks)
      # Azure requires that the vm be recreated for network update,
      # so we need to notify the InstanceUpdater to recreate it
      raise Bosh::Clouds::NotSupported unless (networks.eql?(instance_manager.find(vm_id)))
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM. When
    # VM locality is specified the disk will be placed near the VM so it won't have to move
    # when it's attached later.
    #
    # @param [Integer] size disk size in MB
    # @param [optional, String] vm_id vm id if known of the VM that this disk will
    #                           be attached to
    # @return [String] opaque id later used by {#attach_disk}, {#detach_disk}, and {#delete_disk}
    def create_disk(size, vm_id = nil)
    end

    ##
    # Deletes a disk
    # Will raise an exception if the disk is attached to a VM
    #
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def delete_disk(disk_id)
      vdisk_service.delete_virtual_machine_disk(disk_id)
    end

    # Attaches a disk
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def attach_disk(vm_id, disk_id)
    end

    # Take snapshot of disk
    # @param [String] disk_id disk id of the disk to take the snapshot of
    # @param [Hash] metadata metadata key/value pairs
    # @return [String] snapshot id
    def snapshot_disk(disk_id, metadata={})
      # TODO: Get vhd from 'vhd' container in vm storage account and use blob client to snapshot it
    end

    # Delete a disk snapshot
    # @param [String] snapshot_id snapshot id to delete
    # @return [void]
    def delete_snapshot(snapshot_id)
    end

    # Detaches a disk
    # @param [String] vm_id vm id that was once returned by {#create_vm}
    # @param [String] disk_id disk id that was once returned by {#create_disk}
    # @return [void]
    def detach_disk(vm_id, disk_id)
    end

    # List the attached disks of the VM.
    # @param [String] vm_id is the CPI-standard vm_id (eg, returned from current_vm_id)
    # @return [array[String]] list of opaque disk_ids that can be used with the
    # other disk-related methods on the CPI
    def get_disks(vm_id)
    end


    private

    # TODO: Need to improve cycling of cert to happen only if necessary
    # Makes sure the Azure cert specified in the template is available as a well-known blob
    def prepare_azure_cert
      container_name = 'well-known'
      blob_name = 'api-cert'

      blob_service.create_container(container_name) unless blob_manager.container_exist?(container_name)
      blob_manager.delete_file(container_name, blob_name) if blob_manager.blob_exist?(container_name, blob_name)
      blob_manager.put_file(container_name, blob_name, Azure.config.management_certificate)
      blob_manager.get_file(container_name, blob_name, @seed_api_cert_path)
    end

    ##
    # Checks if options passed to CPI are valid and can actually
    # be used to create all required data structures etc.
    #
    def validate_options
      required_keys = {
          # 'azure' => %w(cert_path subscription_id region default_key_name logical_name),
          'azure' => %w(),
          'registry' => []
      }

      missing_keys = []

      required_keys.each_pair do |key, values|
        values.each do |value|
          if (!options.has_key?(key) || !options[key].has_key?(value))
            missing_keys << "#{key}:#{value}"
          end
        end
      end

      raise ArgumentError, "missing configuration parameters > #{missing_keys.join(', ')}" unless missing_keys.empty?
    end

    def init_azure
      Azure.configure do |config|
        config.management_certificate = File.absolute_path(azure_properties['cert_file']) || @seed_api_cert_path

        config.subscription_id        = azure_properties['subscription_id']
        config.management_endpoint    = @vmm_endpoint_url

        config.storage_account_name = azure_properties['storage_account_name']
        config.storage_access_key = azure_properties['storage_account_access_key']
      end
    end

    def azure_properties
      @azure_properties ||= options.fetch('azure')
    end

    def stemcell_finder
      @stemcell_finder ||= StemcellFinder.new(image_service)
    end

    def instance_manager
      @instance_manager ||= VMManager.new(azure_vm_client, image_service, vnet_manager, storage_manager)
    end

    def affinity_group_manager
      @ag_manager ||= AffinityGroupManager.new(base_service)
    end

    def vnet_manager
      @vnet_manager ||= VirtualNetworkManager.new(vnet_service, affinity_group_manager)
    end

    def stemcell_manager
      @stemcell_creator ||= StemcellManager.new(blob_manager)
    end

    # TODO: Need to make default more 'random' with the abaility to determine it after the fact
    # TODO: as the storage accounts are globally unique accross ALL azure accounts in the world
    def storage_manager
      @storage_manager ||= StorageAccountManager.new(storage_service,
                                                     options['azure']['storage_account_name'] ||
                                                        'boshdefaultstorage')
    end

    def blob_manager
      @blob_manager ||= BlobManager.new(blob_service)
    end

    def cloud_service_service
      @cloud_service_service ||= Azure::CloudServiceManagement::CloudServiceManagementService.new
    end

    def azure_vm_client
      @azure_vm_client ||= Azure::VirtualMachineManagementService.new
    end

    def base_service
      @base_service ||= Azure::BaseManagementService.new
    end

    def image_service
      @image_service ||= Azure::VirtualMachineImageManagementService.new
    end

    def vnet_service
      @vnet_service ||= Azure::VirtualNetworkManagementService.new
    end

    def vdisk_service
      @vdisk_service ||= Azure::VirtualMachineImageManagement::VirtualMachineDiskManagementService.new
    end

    def storage_service
      @storage_service ||= Azure::StorageManagement::StorageManagementService.new
    end

    def blob_service
      @blob_service ||= Azure::BlobService.new
    end
  end
end