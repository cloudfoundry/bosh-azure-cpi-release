module Bosh::AzureCloud
  class BlobManager
    include Helpers

    VHDBlock = Struct.new(:id, :file_start_range, :size, :blob_start_range, :content)
    ThreadFlag = Struct.new(:finish, :fail, :message)

    def initialize(parallel_upload_thread_num)
      @blob_service_client = Azure::BlobService.new
      @parallel_upload_thread_num = parallel_upload_thread_num

      @logger = Bosh::Clouds::Config.logger
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

    def delete_blob_snapshot(container_name, blob_name, snapshot_time)
      @logger.info("delete_blob_snapshot(#{container_name}, #{blob_name}, #{snapshot_time})")
      @blob_service_client.delete_blob(container_name, blob_name, {
        :snapshot => snapshot_time
      })
    end

    def create_page_blob(container_name, file_path, blob_name)
      @logger.info("create_page_blob(#{container_name}, #{file_path}, #{blob_name})")
      begin
        blob_size = File.lstat(file_path).size
        @logger.info("create_page_blob: blob_name: #{blob_name}, blob_size: #{blob_size}")
        
        @logger.info("create_page_blob: Calculate hash for every block")

        upload_page_blob(container_name, blob_name, blob_size, file_path, @parallel_upload_thread_num)
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
        @logger.info("create_empty_vhd_blob: Start to generate vhd footer")
        opts = {
            :type => :fixed,
            :name => "/tmp/footer.vhd", # Only used to initialize Vhd, no local file is generated.
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
        @logger.info("create_empty_vhd_blob: Create empty vhd blob #{blob_name} with size #{blob_size}")
        @blob_service_client.create_page_blob(container_name, blob_name, blob_size, options)
        blob_created = true

        @logger.info("create_empty_vhd_blob: Start to upload vhd footer")

        @blob_service_client.create_blob_pages(container_name, blob_name, vhd_size, blob_size - 1, vhd_footer, options)
      rescue => e
        @blob_service_client.delete_blob(container_name, blob_name) if blob_created
        cloud_error("Failed to create empty vhd blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    def blob_exist?(container_name, blob_name)
      @logger.info("blob_exist?(#{container_name}, #{blob_name})")
      @blob_service_client.get_blob_properties(container_name, blob_name)
      true
    rescue => e
      cloud_error("blob_exist?: #{e.message}\n#{e.backtrace.join("\n")}") unless e.message.include?("(404)")
      false
    end

    def list_blobs(container_name, prefix = nil)
      @logger.info("list_blobs(#{container_name})")
      blobs = Array.new
      options = {}
      options[:prefix] = prefix unless prefix.nil?
      while true do
        temp = @blob_service_client.list_blobs(container_name, options)
        blobs += temp if temp.size > 0
        break if temp.continuation_token.nil? || temp.continuation_token.empty?
        options[:marker] = temp.continuation_token
      end
      blobs
    end

    def snapshot_blob(container_name, blob_name, metadata, snapshot_blob_name)
      @logger.info("snapshot_blob(#{container_name}, #{blob_name}, #{metadata}, #{snapshot_blob_name})")
      snapshot_time = @blob_service_client.create_blob_snapshot(container_name, blob_name, {:metadata => metadata})
      @logger.debug("Snapshot time: #{snapshot_time}")

      begin
        @logger.info("Copying the snapshot of the blob #{container_name}/#{blob_name} to #{container_name}/#{snapshot_blob_name}")
        copy_id, copy_status = @blob_service_client.copy_blob(container_name, snapshot_blob_name, container_name, blob_name, {:source_snapshot => snapshot_time})
        @logger.info("Copy id: #{copy_id}, copy status: #{copy_status}")

        copy_status_description = ""
        while copy_status == "pending" do
          blob_props = @blob_service_client.get_blob_properties(container_name, blob_name)
          if blob_props[:copy_id] != copy_id
            cloud_error("The progress of copying the snapshot of the blob #{container_name}/#{blob_name} to #{container_name}/#{snapshot_blob_name} was interrupted by other copy operations.")
          end

          copy_status = blob_props[:copy_status]
          copy_status_description = blob_props[:copy_status_description]
          @logger.debug("Copying progress: #{blob_props[:copy_progress]}")
        end

        if copy_status == "success"
          @logger.info("Take snapshot of the blob #{container_name}/#{blob_name} successfully.")
        else
          cloud_error("Failed to copy the snapshot of the blob #{container_name}/#{blob_name}: \n\tcopy status: #{copy_status}\n\tcopy description: #{copy_status_description}")
        end
      ensure
        delete_blob_snapshot(container_name, blob_name, snapshot_time)
      end
    end

    private

    def read_content_func(file_path, file_blocks, block_size, thread_num, finish_flag)
      id = 0
      open(file_path, 'rb') do |file|
        while !finish_flag.fail do
          if file_blocks.size > thread_num * 5
            sleep(0.01)
            next
          end

          chunk = nil
          file_start_range = file.pos
          chunk = file.read(block_size)
          if chunk.nil?
            finish_flag.finish = true
            break
          end

          block_is_not_empty = false
          chunk.each_byte do |b|
            if b != "\0"
              block_is_not_empty = true
              break
            end
          end

          if block_is_not_empty
            id += 1
            @logger.debug("read_content_func: id: #{id}, start_range: #{file_start_range}, size: #{chunk.size}")
            block = VHDBlock.new(id, file_start_range, chunk.size, file_start_range, chunk)
            file_blocks.push(block)
          end
        end
      end

      @logger.debug("read_content_func: Exit")
    end

    def upload_page_blob_func(id, container_name, blob_name, options, file_blocks, finish_flag, max_retry_count)
      while !finish_flag.fail do
        block = nil
        begin
          block = file_blocks.pop(true)
        rescue
          break if finish_flag.finish
          sleep(0.01)
          next
        end

        retry_count = 0
        begin
          @logger.debug("upload_page_blob_func: Thread #{id}: Uploading #{block.id}: #{block.blob_start_range}, length: #{block.size}, retry: #{retry_count}")
          @blob_service_client.create_blob_pages(container_name, blob_name, block.blob_start_range,
              block.blob_start_range + block.size - 1, block.content, options)
        rescue => e
          @logger.debug("upload_page_blob_func: Thread #{id}: Failed to create_blob_pages, error: #{e.message}\n#{e.backtrace.join("\n")}")
          retry_count += 1
          if retry_count > max_retry_count
            finish_flag.fail = true
            finish_flag.message = e.message
            break
          end
          retry
        end
      end
      @logger.debug("upload_page_blob_func: Thread #{id}: Exit")
    end

    def upload_page_blob(container_name, blob_name, blob_size, file_path, thread_num)
      blob_created = false

      begin
        options = {
          :timeout => 300 # seconds
        }
        @logger.info("Create page blob #{blob_name} with size #{blob_size}")
        @blob_service_client.create_page_blob(container_name, blob_name, blob_size, options)
        blob_created = true

        @logger.info("Start to upload every block for page blob")
        threads = []
        finish_flag = ThreadFlag.new(false, false, nil)
        file_blocks = Queue.new()

        block_size = 2 * 1024 * 1024

        start_time = Time.new
        threads << Thread.new {
          read_content_func(file_path, file_blocks, block_size, thread_num, finish_flag)
        }
        thread_num.times do |i|
          threads << Thread.new {
            upload_page_blob_func(i + 1, container_name, blob_name, options, file_blocks, finish_flag, 20)
          }
        end

        threads.each { |t| t.join }

        raise finish_flag.message if finish_flag.fail

        duration = Time.new - start_time
        @logger.info("Duration: #{duration.inspect}")
      rescue => e
        @blob_service_client.delete_blob(container_name, blob_name) if blob_created
        cloud_error("Failed to upload page blob: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end
  end
end