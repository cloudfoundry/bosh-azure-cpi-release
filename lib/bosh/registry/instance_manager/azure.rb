#TODO: This is a problem as the parent class is also called Azure and we cant change it unless the plugin itself is named something other than just 'Azure'
#require 'azure'

module Bosh::Registry

  class InstanceManager

    class Azure < InstanceManager

      def initialize(cloud_config)
        validate_options(cloud_config)

        @logger = Bosh::Registry.logger

        @azure_properties = cloud_config["azure"]

        #TODO: This is a problem as the parent class is also called Azure and we cant change it unless the plugin itself is named something other than just 'Azure'
        # Azure.configure do |config|
        #   config.management_certificate = File.absolute_path(@azure_properties['cert_file'])
        #
        #   config.subscription_id        = @azure_properties['subscription_id']
        #   config.management_endpoint    = "https://management.core.windows.net"
        #
        #   config.storage_account_name = @azure_properties['storage_account_name']
        #   config.storage_access_key = @azure_properties['storage_account_access_key']
        # end

        #TODO: This is a problem as the parent class is also called Azure and we cant change it unless the plugin itself is named something other than just 'Azure'
        #@azure = Azure::VirtualMachineManagementService.new
      end

      def validate_options(cloud_config)
        unless cloud_config.has_key?("azure") &&
            cloud_config["azure"].is_a?(Hash) &&
            cloud_config["azure"]["cert_file"] &&
            cloud_config["azure"]["subscription_id"] &&
            cloud_config["azure"]["storage_account_name"] &&
            cloud_config["azure"]["storage_account_access_key"]
          raise ConfigError, "Invalid Azure configuration parameters"
        end
      end

      # Get the list of IPs belonging to this instance
      def instance_ips(instance_id)

        vm_ext = vm_from_yaml(instance_id)

        #TODO: This is a problem as the parent class is also called Azure and we cant change it unless the plugin itself is named something other than just 'Azure'
        #instance = @azure.get_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])

        #[instance.ipaddress]
        []
      rescue AWS::Errors::Base => e
        raise Bosh::Registry::AwsError, "Azure error: #{e}"
      end


      private

      def vm_from_yaml(yaml)
        symbolize_keys(YAML.load(yaml))
      end

    end

  end

end