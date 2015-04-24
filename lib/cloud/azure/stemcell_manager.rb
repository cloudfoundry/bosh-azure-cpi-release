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
      stemcell = stemcells.find do |image_name|
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

    def stemcells
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
    rescue => e
      cloud_error("Failed to list stemcells: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def create_stemcell(image_path, cloud_properties)
      vhd_path = extract_image(image_path)

      logger.info("Start to upload VHD")
      stemcell_name = "bosh-image-#{SecureRandom.uuid}"
      @blob_manager.create_page_blob(container_name, vhd_path, "#{stemcell_name}.vhd")

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
    def extract_image(image_path)
      logger.info("Unpacking image: #{image_path}")
      tmp_dir = Dir.mktmpdir('sc-')
      run_command("tar -zxf #{image_path} -C #{tmp_dir}")
      "#{tmp_dir}/root.vhd"
    end

    def run_command(command)
      output, status = Open3.capture2e(command)
      if status.exitstatus != 0
        cloud_error("'#{command}' failed with exit status=#{status.exitstatus} [#{output}]")
      end
    end
  end
end
