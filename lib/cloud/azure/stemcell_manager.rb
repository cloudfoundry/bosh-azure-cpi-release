require 'azure'
require 'date'
require_relative 'helpers'

module Bosh::AzureCloud
  class StemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, image_client)
      @blob_manager = blob_manager
      @image_client = image_client
    end

    # TODO: Need to list all private stemcells as well and make this metod search them
    def find_stemcell_by_name(name)
      stemcell = list_stemcells.find do |image_name|
        image_name == name
      end

      raise Bosh::Clouds::CloudError, "Given image name '#{name}' does not exist!" if stemcell.nil?
      stemcell
    end

    def stemcell_exist?(name)
      begin
        find_stemcell_by_name name
      rescue
        return false
      end
      true
    end

    # TODO: Need to set more predictable name in request as Azure returns an empty body... not sure why...
    def imageize_vhd(vm_id, deployment_name)
      vm = vm_from_yaml(vm_id)
      # TODO: Need to set body
      # See: http://msdn.microsoft.com/en-us/library/azure/dn499768.aspx
      handle_response post("https://management.core.windows.net/#{Azure.config.subscription_id}/" \
                           "services/hostedservices/#{vm[:cloud_service_name]}/deployments/" \
                           "#{deployment_name}/roleinstances/#{vm[:vm_name]}/Operations",
                           "<CaptureRoleAsVMImageOperation xmlns=\"http://schemas.microsoft.com/windowsazure\" " \
                           "xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" \
                           '<OperationType>CaptureRoleAsVMImageOperation</OperationType>' \
                           '<OSState>Generalized</OSState>' \
                           "<VMImageName>BOSH-Stemcell-#{vm[:cloud_service_name]}-#{(0..16).to_a.map{|a| rand(16).to_s(16)}.join}</VMImageName>" \
                           '<VMImageLabel>BOSH-Stemcell</VMImageLabel>' \
                           "<Description>Auto created by BOSH on #{DateTime.now}</Description>" \
                           '</CaptureRoleAsVMImageOperation>')
    end


    def delete_image(image_name)
      handle_response delete("https://management.core.windows.net/#{Azure.config.subscription_id}/" \
                             "services/vmimages/#{image_name}")
    end

    def list_stemcells
      list_private_images.concat(list_public_images)
    end


    private

    def list_public_images
      public_images = []
      @image_client.list_virtual_machine_images.each { |image|
        public_images << image.name
      }
      public_images
    end

    def list_private_images
      private_images = []
      response = handle_response get("https://management.core.windows.net/#{Azure.config.subscription_id}/services/vmimages")
      response['VMImage'].each { |image|
        private_images << image['Name'].first
      }
      private_images
    end
  end
end