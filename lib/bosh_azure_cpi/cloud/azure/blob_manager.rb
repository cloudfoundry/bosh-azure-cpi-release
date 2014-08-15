
module Bosh::AzureCloud
  class BlobManager

    def initialize(blob_service_client)
      @blob_service_client = blob_service_client
    end

    def put_file(container_name, blob_name, file_path)
      content = File.open(file_path, 'rb') { |file| file.read }
      blob_service.create_block_blob(container_name, blob_name, content)
    end

    def blob_exist?(container_name, blob_name)
      list_blobs(container_name).each do |blob|
        return true if (blob.name.eql?(blob_name))
      end

      return false
    end

    def list_blobs(container_name)
      @blob_service_client.list_blobs(container_name)
    end

    def get_file(container_name, blob_name, file_path)
      blob, content = @blob_service_client.get_blob(container_name, blob_name)
      File.open(file_path, 'wb') { |f| f.write(content) }
    end

    def container_exist?(container_name)
      @blob_service_client.list_containers.each do |container|
        return true if (container.name.eql?(container_name))
      end

      return false
    end
  end
end