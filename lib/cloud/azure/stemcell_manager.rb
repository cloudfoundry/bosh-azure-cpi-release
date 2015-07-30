module Bosh::AzureCloud
  class StemcellManager
    STEMCELL_CONTAINER = 'stemcell'
    STEMCELL_PREFIX    = 'bosh-stemcell'

    include Bosh::Exec
    include Helpers

    def initialize(blob_manager)
      @blob_manager = blob_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def has_stemcell?(name)
      @logger.info("has_stemcell?(#{name})")
      @blob_manager.blob_exist?(STEMCELL_CONTAINER, "#{name}.vhd")
    end

    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")
      @blob_manager.delete_blob(STEMCELL_CONTAINER, "#{name}.vhd") if has_stemcell?(name)
    end

    def stemcells
      @logger.info("stemcells")
      @blob_manager.list_blobs(STEMCELL_CONTAINER, STEMCELL_PREFIX)
    end

    def create_stemcell(image_path, cloud_properties)
      @logger.info("create_stemcell(#{image_path}, #{cloud_properties})")

      unless @blob_manager.container_exist?(STEMCELL_CONTAINER)
        @blob_manager.create_container(STEMCELL_CONTAINER)
      end

      stemcell_name = nil
      Dir.mktmpdir('sc-') do |tmp_dir|
        @logger.info("Unpacking image: #{image_path}")
        run_command("tar -zxf #{image_path} -C #{tmp_dir}")
        @logger.info("Start to upload VHD")
        stemcell_name = "#{STEMCELL_PREFIX}-#{SecureRandom.uuid}"
        @blob_manager.create_page_blob(STEMCELL_CONTAINER, "#{tmp_dir}/root.vhd", "#{stemcell_name}.vhd")
      end
      stemcell_name
    end

    def get_stemcell_uri(name)
      @logger.info("get_stemcell_uri(#{name})")
      @blob_manager.get_blob_uri(STEMCELL_CONTAINER, "#{name}.vhd")
    end

    private

    def run_command(command)
      output, status = Open3.capture2e(command)
      if status.exitstatus != 0
        cloud_error("'#{command}' failed with exit status=#{status.exitstatus} [#{output}]")
      end
    end
  end
end