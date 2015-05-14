module Bosh::AzureCloud
  class StemcellManager
    STEM_CELL_CONTAINER = 'stemcell'    

    attr_reader   :container_name
    attr_accessor :logger

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager)
      @container_name = STEM_CELL_CONTAINER
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def find_stemcell_by_name(name)
      @logger.info("find_stemcell_by_name(#{name})")
      stemcells.find { |stemcell| stemcell.name == "#{name}.vhd" }
    end

    def has_stemcell?(name)
      @logger.info("has_stemcell?(#{name})")
      !find_stemcell_by_name(name).nil?
    end

    def delete_image(name)
      @logger.info("delete_image(#{name})")
      @blob_manager.delete_blob(container_name, "#{name}.vhd")
    end

    def stemcells
      @logger.info("stemcells")
      @blob_manager.list_blobs(container_name)
    end

    def create_stemcell(image_path, cloud_properties)
      @logger.info("create_stemcell(#{image_path}, #{cloud_properties})")
      vhd_path = extract_image(image_path)
      logger.info("Start to upload VHD")
      stemcell_name = "bosh-image-#{SecureRandom.uuid}"
      @blob_manager.create_page_blob(container_name, vhd_path, "#{stemcell_name}.vhd")
      stemcell_name
    end

    def get_stemcell_uri(name)
      @logger.info("get_stemcell_uri(#{name})")
      @blob_manager.get_blob_uri(STEM_CELL_CONTAINER, "#{name}.vhd")
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