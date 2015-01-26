
module Bosh::AzureCloud
  class StemcellManager
    IMAGE_FAMILY = 'bosh'

    attr_reader   :container_name
    attr_accessor :logger
    
    include Bosh::Exec
    include Helpers

    def initialize(container_name, storage_manager, blob_manager)
      @container_name = container_name
      @storage_manager = storage_manager
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def find_stemcell_by_name(name)
      stemcell = list_stemcells.find do |image_name|
        image_name == name
      end

      raise Bosh::Clouds::CloudError, "Given image name '#{name}' does not exist!" if stemcell.nil?
      stemcell
    end

    def has_stemcell?(name)
      begin
        find_stemcell_by_name name
      rescue
        return false
      end
      true
    end
    
    def delete_image(image_name)
      http_delete("services/images/#{image_name}?comp=media")
    end

    def list_stemcells
      os_images = []
      storage_affinity_group = @storage_manager.get_storage_affinity_group
      
      response = handle_response http_get("/services/images")
      response.css('Images OSImage').each do |image|
        image_family = xml_content(image, 'ImageFamily')
        category = xml_content(image, 'Category')
        affinity_group = xml_content(image, 'AffinityGroup')
        
        if image_family == IMAGE_FAMILY && category == 'User' && affinity_group == storage_affinity_group
          os_images << xml_content(image, 'Name')
        end
      end
      os_images
    end

    def create_stemcell(image_path, cloud_properties)
      stemcell_name = "bosh-image-#{SecureRandom.uuid}"
      
      logger.info("Start to upload VHD")
      @blob_manager.create_page_blob(container_name, image_path, "#{stemcell_name}.vhd")
      
      begin
        logger.info("Start to create an image with the uploaded VHD")
        handle_response http_post("/services/images",
                             "<OSImage xmlns=\"http://schemas.microsoft.com/windowsazure\" " \
                             "xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" \
                             "<Label>#{IMAGE_FAMILY}</Label>" \
                             "<MediaLink>#{@storage_manager.get_storage_blob_endpoint}#{container_name}/#{stemcell_name}.vhd</MediaLink>" \
                             "<Name>#{stemcell_name}</Name>" \
                             '<OS>Linux</OS>' \
                             '<Description>BOSH Stemcell</Description>' \
                             "<ImageFamily>#{IMAGE_FAMILY}</ImageFamily>" \
                             '</OSImage>')
      rescue => e
        @blob_manager.delete_blob(container_name, "#{stemcell_name}.vhd")
        cloud_error("Failed to create stemcell: #{e.message}\n#{e.backtrace.join("\n")}")
      end
      
      stemcell_name
    end

    private
  end
end