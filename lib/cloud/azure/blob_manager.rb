module Bosh::AzureCloud
  class BlobManager
    attr_accessor :logger
    include Helpers
    
    VHDBlock = Struct.new(:id, :file_start_range, :size, :blob_start_range, :content)
    ThreadFlag = Struct.new(:finish)
    
    def initialize
      @blob_service_client = Azure::BlobService.new

      @logger = Bosh::Clouds::Config.logger
    end

    def create_container(container_name)
      @logger.info("create_container(#{container_name})")
      @blob_service_client.create_container(container_name) unless container_exist?(container_name)
    end

    def container_exist?(container_name)
      @logger.info("container_exist?(#{container_name})")
      container = @blob_service_client.list_containers.find { |container| container.name.eql?(container_name) }
      !container.nil?
    end

    def delete_blob(container_name, blob_name)
      @logger.info("delete_blob(#{container_name}, #{blob_name})")
      @blob_service_client.delete_blob(container_name, blob_name, {
        :delete_snapshots => :include
      })
    end

    def get_blob_uri(container_name, blob_name)
      @logger.info("get_blob_uri(#{container_name}, #{blob_name})")
      "#{Azure.config.storage_blob_host}/#{container_name}/#{blob_name}"
    end

    def get_blob_size(uri)
      @logger.info("get_blob_size?(#{uri})")
      container = uri.split("/")[3..3][0]
      blob_name = uri.split("/")[4..-1][0]
      prop = @blob_service_client.get_blob_properties(container, blob_name)
      prop.properties[:content_length]
    end

    def delete_blob_snapshot(container_name, blob_name, snapshot_time)
      @logger.info("delete_blob_snapshot(#{container_name}, #{blob_name}, #{snapshot_time})")
      @blob_service_client.delete_blob(container_name, blob_name, {
        :snapshot => snapshot_time
      })
    end

    def create_block_blob(container_name, file_path, blob_name)
      @logger.info("create_block_blob(#{container_name}, #{file_path}, #{blob_name})")
      block_list = []
      counter    = 1

      open(file_path, 'rb') do |f|
        f.each_chunk {|chunk|
          block_id = counter.to_s.rjust(5, '0')
          block_list << [block_id, :uncommitted]

          options = {
            :content_md5 => Base64.strict_encode64(Digest::MD5.digest(chunk)),
            :timeout     => 300 # seconds
          }

          md5 = @blob_service_client.create_blob_block(container_name, blob_name, block_id, chunk, options)
          logger.debug("Put file: counter: #{counter}, block_id: #{block_id}")
          counter += 1
        }
      end

      logger.info("Commit file: block_list size: #{block_list.length}")
      @blob_service_client.commit_blob_blocks(container_name, blob_name, block_list)
    end

    def create_page_blob(container_name, file_path, blob_name)
      @logger.info("create_page_blob(#{container_name}, #{file_path}, #{blob_name})")
      begin
        blob_size = File.lstat(file_path).size
        logger.info("create_page_blob: blob_name: #{blob_name}, blob_size: #{blob_size}")
        
        logger.info("create_page_blob: Calculate hash for every block")

        upload_page_blob(container_name, blob_name, blob_size, file_path, 36)
      rescue => e
        cloud_error("Failed to upload page blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    ##
    # Creates an empty vhd blob.
    #
    # @param [String] container_name container name
    # @param [String] blob_name vhd name
    # @param [Integer] blob_size_in_gb blob size in GB
    # @return [void]
    def create_empty_vhd_blob(container_name, blob_name, blob_size_in_gb)
      @logger.info("create_empty_vhd_blob(#{container_name}, #{blob_name}, #{blob_size_in_gb})")
      blob_created = false
      begin
        logger.info("create_empty_vhd_blob: Start to generate vhd footer")
        opts = {
            :type => :fixed,
            :name => "/tmp/tmp.vhd",
            :size => blob_size_in_gb
        }
        vhd_footer = Vhd::Library.new(opts).footer.values.join

        # Reference Virtual Hard Disk Image Format Specification
        # http://download.microsoft.com/download/f/f/e/ffef50a5-07dd-4cf8-aaa3-442c0673a029/Virtual%20Hard%20Disk%20Format%20Spec_10_18_06.doc
        vhd_size = blob_size_in_gb * 1024 * 1024 * 1024
        blob_size = vhd_size + 512
        options = {
          :timeout => 300 # seconds
        }
        logger.info("create_empty_vhd_blob: Create empty vhd blob #{blob_name} with size #{blob_size}")
        @blob_service_client.create_page_blob(container_name, blob_name, blob_size, options)
        blob_created = true

        logger.info("create_empty_vhd_blob: Start to upload vhd footer")

        @blob_service_client.create_blob_pages(container_name, blob_name, vhd_size, blob_size - 1, vhd_footer, options)
      rescue => e
        @blob_service_client.delete_blob(container_name, blob_name) if blob_created
        cloud_error("Failed to create empty vhd blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def blob_exist?(container_name, blob_name)
      logger.info("blob_exist?(#{container_name}, #{blob_name})")
      blob = list_blobs(container_name).find { |blob| blob.name.eql?(blob_name) }

      !blob.nil?
    end

    def list_blobs(container_name)
      logger.info("list_blobs(#{container_name})")
      @blob_service_client.list_blobs(container_name)
    end

    def get_blob(container_name, blob_name, file_path)
      logger.info("get_blob(#{container_name}, #{blob_name}, #{file_path})")
      blob, content = @blob_service_client.get_blob(container_name, blob_name)
      File.open(file_path, 'wb') { |f| f.write(content) }
    end

    def snapshot_blob(container_name, blob_name, metadata, snapshot_blob_name)
      logger.info("snapshot_blob(#{container_name}, #{blob_name}, #{metadata}, #{snapshot_blob_name})")
      snapshot_time = @blob_service_client.create_blob_snapshot(container_name, blob_name, {:metadata => metadata})
      logger.debug("Snapshot time: #{snapshot_time}")

      begin
        logger.info("Copying the snapshot of the blob #{container_name}/#{blob_name} to #{container_name}/#{snapshot_blob_name}")
        copy_id, copy_status = @blob_service_client.copy_blob(container_name, snapshot_blob_name, container_name, blob_name, {:source_snapshot => snapshot_time})
        logger.info("Copy id: #{copy_id}, copy status: #{copy_status}")

        copy_status_description = ""
        while copy_status == "pending" do
          blob_props = @blob_service_client.get_blob_properties(container_name, blob_name)
          if blob_props[:copy_id] != copy_id
            cloud_error("The progress of copying the snapshot of the blob #{container_name}/#{blob_name} to #{container_name}/#{snapshot_blob_name} was interrupted by other copy operations.")
          end

          copy_status = blob_props[:copy_status]
          copy_status_description = blob_props[:copy_status_description]
          logger.debug("Copying progress: #{blob_props[:copy_progress]}")
        end

        if copy_status == "success"
          logger.info("Take snapshot of the blob #{container_name}/#{blob_name} successfully.")
        else
          cloud_error("Failed to copy the snapshot of the blob #{container_name}/#{blob_name}: \n\tcopy status: #{copy_status}\n\tcopy description: #{copy_status_description}")
        end
      ensure
        delete_blob_snapshot(container_name, blob_name, snapshot_time)
      end
    end

    private

    def read_content_func(file_mutex, file_path, file_blocks, block_size, finish_flag, max_count)
      count = 0
      id = 0
      open(file_path, 'rb') do |file|
        while true do
          file_mutex.synchronize do
            count = file_blocks.size
          end

          if count >= max_count
            sleep(0.01)
            next
          end

          chunk = nil
          file_start_range = file.pos
          chunk = file.read(block_size)
          break if chunk.nil?

          logger.debug("read_content_func: id: #{id}, start_range: #{file_start_range}, size: #{chunk.size}")

          id += 1
          block = VHDBlock.new(id, file_start_range, chunk.size, file_start_range, chunk)
          file_mutex.synchronize do
            file_blocks.push(block)
          end
        end
      end

      logger.debug("read_content_func: Read all content")
      finish_flag.finish = true
    end

    def upload_page_blob_func(id, container_name, blob_name, options, file_mutex, file_blocks, ignore_hash, finish_flag)
      while true do
        block = nil
        file_mutex.synchronize do
          block = file_blocks.pop()
        end

        if block.nil?
          if finish_flag.finish
            logger.debug("upload_page_blob_func: Thread #{id}: Done")
            return
          end
          sleep(0.01)
        else
          hash = Digest::MD5.hexdigest(block.content)
          # Skip empty content
          if hash == ignore_hash
            logger.debug("upload_page_blob_func: Thread #{id}: Skip empty content #{block.id}: #{block.blob_start_range}, length: #{block.size}, hash: #{hash}")
          else
            logger.debug("upload_page_blob_func: Thread #{id}: Uploading #{block.id}: #{block.blob_start_range}, length: #{block.size}, hash: #{hash}")
            @blob_service_client.create_blob_pages(container_name, blob_name, block.blob_start_range,
                block.blob_start_range + block.size - 1, block.content, options)
          end
        end
      end
    end

    def upload_page_blob(container_name, blob_name, blob_size, file_path, thread_num)
      blob_created = false

      begin
        options = {
          :timeout => 300 # seconds
        }
        logger.info("Create page blob #{blob_name} with size #{blob_size}")
        @blob_service_client.create_page_blob(container_name, blob_name, blob_size, options)
        blob_created = true

        logger.info("Start to upload every block for page blob")
        threads = []
        finish_flag = ThreadFlag.new(false)
        file_blocks = Array.new
        file_mutex = Mutex.new

        block_size = 2**22
        ignore_hash = get_ignore_hash_for_empty_block(block_size)

        start_time = Time.new
        threads << Thread.new {
          read_content_func(file_mutex, file_path, file_blocks, block_size, finish_flag, 2 * thread_num)
        }
        thread_num.times do |i|
          threads << Thread.new {
            upload_page_blob_func(i + 1, container_name, blob_name, options, file_mutex, file_blocks, ignore_hash, finish_flag)
          }
        end

        threads.each { |t| t.join }

        duration = Time.new - start_time
        logger.info("Duration: #{duration.inspect}")
      rescue => e
        @blob_service_client.delete_blob(container_name, blob_name) if blob_created
        cloud_error("Failed to upload page blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def get_ignore_hash_for_empty_block(size)
      File.open('/tmp/calaculate_hash_for_empty_content', 'w+') do |f|
        f.truncate(size)
        hash = Digest::MD5.hexdigest(f.read)
      end
    end
  end
  
  class ::File
    def each_chunk(chunk_size=2**20)
      yield read(chunk_size) until eof?
    end
  end
end