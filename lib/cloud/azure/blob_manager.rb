module Bosh::AzureCloud
  class BlobManager
    attr_accessor :logger
    
    include Helpers
    
    VHDBlock = Struct.new(:id, :hash, :file_start_range, :size, :blob_start_range)
    
    def initialize
      @blob_service_client = Azure::BlobService.new

      @logger = Bosh::Clouds::Config.logger
    end

    def create_container(container_name)
      @blob_service_client.create_container(container_name) unless container_exist?(container_name)
    end

    def container_exist?(container_name)
      @blob_service_client.list_containers.each do |container|
        return true if (container.name.eql?(container_name))
      end

      return false
    end

    def delete_blob(container_name, blob_name)
      @blob_service_client.delete_blob(container_name, blob_name, {
        :delete_snapshots => :include
      })
    end

    def delete_blob_snapshot(container_name, blob_name, snapshot_time)
      @blob_service_client.delete_blob(container_name, blob_name, {
        :snapshot => snapshot_time
      })
    end

    def create_block_blob(container_name, file_path, blob_name)
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
      begin
        blob_size = File.lstat(file_path).size
        logger.info("create_page_blob: blob_name: #{blob_name}, blob_size: #{blob_size}")
        
        logger.info("create_page_blob: Calculate hash for every block")
        block_size = 2**20
        blocks = Array.new
        
        thread_num = 10
        threads = []
        mutex = Mutex.new

        work_num = blob_size / (thread_num * block_size)

        start_time = Time.new
        File.open(file_path, 'rb') do |file|
          thread_num.times do |i|
            # MD5 hash of an empty content of a 2**20 block is b6d81b360a5672d80c27430f39153e2c
            threads << Thread.new {
              calculate_hash(i + 1, mutex, blocks, block_size, 'b6d81b360a5672d80c27430f39153e2c',
                file, i * work_num * block_size, (i + 1) == thread_num ? nil : work_num)
            }
          end
          threads.each { |t| t.join }
        end

        upload_page_blob(container_name, file_path, blocks, blob_name, blob_size, thread_num)
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
      begin
        file_path = "/tmp/tmp.vhd"
        logger.info("create_empty_vhd_blob: Start to create vhd footer")
        opts = {
            :type => :fixed,
            :name => file_path,
            :size => blob_size_in_gb
        }
        generator = Vhd::Library.new(opts)
        generator.create

        logger.info("create_empty_vhd_blob: Start to upload vhd footer")
        # Reference Virtual Hard Disk Image Format Specification
        # http://download.microsoft.com/download/f/f/e/ffef50a5-07dd-4cf8-aaa3-442c0673a029/Virtual%20Hard%20Disk%20Format%20Spec_10_18_06.doc
        vhd_size = blob_size_in_gb * 1024 * 1024 * 1024
        blob_size = vhd_size + 512
        
        blocks = Array.new
        blocks.push(VHDBlock.new(1, "", 0, 512, vhd_size))

        upload_page_blob(container_name, file_path, blocks, blob_name, blob_size)
      rescue => e
        cloud_error("Failed to create empty vhd blob: #{e.message}\n#{e.backtrace.join("\n")}")
      ensure
        File.delete(file_path) if File.exists?(file_path)
      end
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

    def get_blob(container_name, blob_name, file_path)
      blob, content = @blob_service_client.get_blob(container_name, blob_name)
      File.open(file_path, 'wb') { |f| f.write(content) }
    end

    def snapshot_blob(container_name, blob_name, metadata, snapshot_blob_name)
      logger.info("Taking snapshot for the blob #{container_name}/#{blob_name}")
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
    
    def upload_page_blob(container_name, file_path, blocks, blob_name, blob_size, thread_num = 1)
      blob_created = false

      begin
        logger.info("")
        options = {
          :timeout => 300 # seconds
        }
        logger.info("Create page blob #{blob_name} with size #{blob_size}")
        @blob_service_client.create_page_blob(container_name, blob_name, blob_size, options)
        blob_created = true

        threads = []
        mutex = Mutex.new
        logger.info("Start to upload every block for page blob")
        open(file_path, 'rb') do |file|
          thread_num.times do |i|
            threads << Thread.new {
              upload_block(container_name, i + 1, mutex, blocks, file, blob_name, options)
            }
          end
          threads.each { |t| t.join }
        end
      rescue => e
        @blob_service_client.delete_blob(container_name, blob_name) if blob_created
        cloud_error("Failed to upload page blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def calculate_hash(id, mutex, hash_blocks, block_size, ignore_hash, file, start_index, num)
      i = 0
      while (num.nil? || i < num) do
        chunk = nil
        start_range = start_index + i * block_size
        mutex.synchronize do
          file.seek(start_range)
          chunk = file.read(block_size)
        end
        break if chunk.nil?
        hash = Digest::MD5.hexdigest(chunk)
        logger.debug("Thread #{id}: Read content from #{start_range}, size: #{chunk.size}, hash: #{hash}")
        # Skip empty content
        if hash != ignore_hash
          mutex.synchronize do
            hash_blocks.push(VHDBlock.new(hash_blocks.size, hash, start_range, chunk.size, start_range))
          end
        end
        i += 1
      end
    end

    def upload_block(container_name, id, mutex, hash_blocks, file, blob_name, options)
      loop do
        block = nil
        chunk = nil

        mutex.synchronize do
          block = hash_blocks.pop
          return if block.nil?
          file.seek(block.file_start_range)
          chunk = file.read(block.size)
        end
        logger.debug("Thread #{id}: Uploading #{block.id}: #{block.blob_start_range}, length: #{block.size}, hash: #{block.hash}")
        @blob_service_client.create_blob_pages(container_name, blob_name, block.blob_start_range,
            block.blob_start_range + block.size - 1, chunk, options)
      end
    end

  end
  
  class ::File
    def each_chunk(chunk_size=2**20)
      yield read(chunk_size) until eof?
    end
  end
end