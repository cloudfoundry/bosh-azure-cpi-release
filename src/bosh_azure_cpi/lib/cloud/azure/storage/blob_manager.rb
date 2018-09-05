# frozen_string_literal: true

module Bosh::AzureCloud
  class BlobManager
    include Helpers

    MAX_CHUNK_SIZE = 2 * 1024 * 1024  # 2MB
    TIMEOUT_FOR_BLOB_OPERATIONS = 120 # Timeout in seconds for Blob Service Operations. https://docs.microsoft.com/en-us/rest/api/storageservices/fileservices/setting-timeouts-for-blob-service-operations

    def initialize(azure_config, azure_client)
      @parallel_upload_thread_num = azure_config.parallel_upload_thread_num
      @azure_config = azure_config
      @azure_client = azure_client
      @empty_chunk_content = Array.new(MAX_CHUNK_SIZE, 0).pack('c*')
      @logger = Bosh::Clouds::Config.logger
      @blob_client_mutex = Mutex.new
      @storage_accounts = {}
    end

    def delete_blob(storage_account_name, container_name, blob_name)
      @logger.info("delete_blob(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        options = {
          delete_snapshots: :include
        }
        options = merge_storage_common_options(options)
        @logger.info("delete_blob: Calling delete_blob(#{container_name}, #{blob_name}, #{options})")
        @blob_service_client.delete_blob(container_name, blob_name, options)
      end
    end

    def get_sas_blob_uri(storage_account_name, container_name, blob_name)
      @logger.info("get_blob_uri(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        storage_account = @storage_accounts[storage_account_name]
        generator = Azure::Storage::Core::Auth::SharedAccessSignature.new(storage_account_name, storage_account[:key])
        token = generator.generate_service_sas_token(
          "#{container_name}/#{blob_name}",
          service: 'b', resource: 'b', permissions: 'r', protocol: 'https',
          expiry: (Time.new + 3600 * 24 * 7).utc.iso8601 # one week is enough for copy blob and so on.
        )
        "#{@azure_storage_client.storage_blob_host}/#{container_name}/#{blob_name}?#{token}"
      end
    end

    def get_blob_uri(storage_account_name, container_name, blob_name)
      @logger.info("get_blob_uri(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        "#{@azure_storage_client.storage_blob_host}/#{container_name}/#{blob_name}"
      end
    end

    def get_blob_size_in_bytes(storage_account_name, container_name, blob_name)
      @logger.info("get_blob_size_in_bytes(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        @blob_service_client.get_blob_properties(container_name, blob_name).properties[:content_length]
      end
    end

    def delete_blob_snapshot(storage_account_name, container_name, blob_name, snapshot_time)
      @logger.info("delete_blob_snapshot(#{storage_account_name}, #{container_name}, #{blob_name}, #{snapshot_time})")
      _initialize_blob_client(storage_account_name) do
        options = {
          snapshot: snapshot_time
        }
        options = merge_storage_common_options(options)
        @logger.info("delete_blob_snapshot: Calling delete_blob(#{container_name}, #{blob_name}, #{options})")
        @blob_service_client.delete_blob(container_name, blob_name, options)
      end
    end

    def create_page_blob(storage_account_name, container_name, file_path, blob_name, metadata)
      @logger.info("create_page_blob(#{storage_account_name}, #{container_name}, #{file_path}, #{blob_name}, #{metadata})")
      # Disable debug_mode because we never want to print the content of VHD in the logs
      _initialize_blob_client(storage_account_name, true) do
        blob_created = false
        begin
          file_size = File.lstat(file_path).size
          options = {
            timeout: TIMEOUT_FOR_BLOB_OPERATIONS,
            metadata: encode_metadata(metadata)
          }
          _create_page_blob(container_name, blob_name, file_size, options)
          blob_created = true

          _upload_page_blob(container_name, blob_name, file_path, @parallel_upload_thread_num)
        rescue StandardError => e
          @blob_service_client.delete_blob(container_name, blob_name, options) if blob_created
          cloud_error("Failed to upload page blob: inspect:#{e.inspect}\n backtrace:#{e.backtrace.join("\n")}")
        end
      end
    end

    def create_empty_page_blob(storage_account_name, container_name, blob_name, blob_size_in_kb, metadata)
      @logger.info("create_empty_page_blob(#{storage_account_name}, #{container_name}, #{blob_name}, #{blob_size_in_kb}, #{metadata})")
      _initialize_blob_client(storage_account_name) do
        begin
          options = {
            timeout: TIMEOUT_FOR_BLOB_OPERATIONS,
            metadata: encode_metadata(metadata)
          }
          blob_size = blob_size_in_kb * 1024
          @logger.info("create_empty_page_blob: Calling _create_page_blob(#{container_name}, #{blob_name}, #{blob_size}, #{options})")
          _create_page_blob(container_name, blob_name, blob_size, options)
        rescue StandardError => e
          cloud_error("Failed to create empty page blob: inspect:#{e.inspect}\n backtrace:#{e.backtrace.join("\n")}")
        end
      end
    end

    def create_vhd_page_blob(storage_account_name, container_name, file_path, blob_name, metadata)
      @logger.info("create_vhd_page_blob(#{storage_account_name}, #{container_name}, #{file_path}, #{blob_name}, #{metadata})")
      _initialize_blob_client(storage_account_name, true) do
        blob_created = false
        begin
          # create page blob first
          vhd_size = File.lstat(file_path).size

          options = {
            timeout: TIMEOUT_FOR_BLOB_OPERATIONS,
            metadata: encode_metadata(metadata)
          }
          blob_size = vhd_size + 512
          @logger.info("create_vhd_page_blob: Calling _create_page_blob(#{container_name}, #{blob_name}, #{blob_size}, #{options})")
          _create_page_blob(container_name, blob_name, blob_size, options)

          blob_created = true
          # upload page blob
          _upload_page_blob(container_name, blob_name, file_path, @parallel_upload_thread_num)

          options = merge_storage_common_options
          # write the vhd footer.
          @logger.info("create_vhd_page_blob: Calling put_blob_pages(#{container_name}, #{blob_name}, #{vhd_size}, #{blob_size - 1}, [VHD-FOOTER], #{options})")
          vhd_footer = VHDUtils.generate_footer(vhd_size).values.join
          @blob_service_client.put_blob_pages(container_name, blob_name, vhd_size, blob_size - 1, vhd_footer, options)
        rescue StandardError => e
          if blob_created
            options = merge_storage_common_options
            @logger.info("create_vhd_page_blob: Calling delete_blob(#{container_name}, #{blob_name}, #{options})")
            @blob_service_client.delete_blob(container_name, blob_name, options)
          end
          cloud_error("Failed to upload page blob: inspect:#{e.inspect}\n backtrace:#{e.backtrace.join("\n")}")
        end
      end
    end

    ##
    # Creates an empty vhd blob.
    #
    # @param [String] container_name container name
    # @param [String] blob_name vhd name
    # @param [Integer] blob_size_in_gb blob size in GiB
    # @param [Boolean] storage_account_name Is premium or not.
    # @return [void]
    def create_empty_vhd_blob(storage_account_name, container_name, blob_name, blob_size_in_gb)
      @logger.info("create_empty_vhd_blob(#{storage_account_name}, #{container_name}, #{blob_name}, #{blob_size_in_gb})")
      blob_created = false
      _initialize_blob_client(storage_account_name) do
        begin
          @logger.info('create_empty_vhd_blob: Start to generate vhd footer')
          vhd_size = blob_size_in_gb * 1024 * 1024 * 1024

          vhd_footer = VHDUtils.generate_footer(vhd_size).values.join
          blob_size = vhd_size + 512
          options = {
            timeout: TIMEOUT_FOR_BLOB_OPERATIONS
          }
          @logger.info("create_empty_vhd_blob: Calling _create_page_blob(#{container_name}, #{blob_name}, #{blob_size}, #{options})")
          _create_page_blob(container_name, blob_name, blob_size, options)
          blob_created = true

          @logger.info('create_empty_vhd_blob: Start to upload vhd footer')

          options = merge_storage_common_options(options)
          # Do not log vhd_footer because its size is 512 bytes.
          @logger.info("create_empty_vhd_blob: Calling put_blob_pages(#{container_name}, #{blob_name}, #{vhd_size}, #{blob_size - 1}, [VHD-FOOTER], #{options})")
          @blob_service_client.put_blob_pages(container_name, blob_name, vhd_size, blob_size - 1, vhd_footer, options)
        rescue StandardError => e
          if blob_created
            options = merge_storage_common_options
            @logger.info("create_empty_vhd_blob: Calling delete_blob(#{container_name}, #{blob_name}, #{options})")
            @blob_service_client.delete_blob(container_name, blob_name, options)
          end
          cloud_error("create_empty_vhd_blob: Failed to create empty vhd blob: inspect:#{e.inspect}\nbacktrace:#{e.backtrace.join("\n")}")
        end
      end
    end

    def get_blob_properties(storage_account_name, container_name, blob_name)
      @logger.info("get_blob_properties(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        begin
          options = merge_storage_common_options
          @logger.info("get_blob_properties: Calling get_blob_properties(#{container_name}, #{blob_name}, #{options})")
          blob = @blob_service_client.get_blob_properties(container_name, blob_name, options)
          blob.properties
        rescue StandardError => e
          cloud_error("get_blob_properties: #{e.inspect}\n#{e.backtrace.join("\n")}") unless e.message.include?('(404)')
          nil
        end
      end
    end

    def get_blob_metadata(storage_account_name, container_name, blob_name)
      @logger.info("get_blob_metadata(#{storage_account_name}, #{container_name}, #{blob_name})")
      _initialize_blob_client(storage_account_name) do
        begin
          options = merge_storage_common_options
          @logger.info("get_blob_metadata: Calling get_blob_metadata(#{container_name}, #{blob_name}, #{options})")
          blob = @blob_service_client.get_blob_metadata(container_name, blob_name, options)
          blob.metadata
        rescue StandardError => e
          cloud_error("get_blob_metadata: inspect:#{e.inspect}\nbacktrace:#{e.backtrace.join("\n")}") unless e.message.include?('(404)')
          nil
        end
      end
    end

    # metadata names must adhere to the naming rules for C# identifiers (http://msdn.microsoft.com/library/aa664670%28VS.71%29.aspx)
    def set_blob_metadata(storage_account_name, container_name, blob_name, metadata)
      @logger.info("set_blob_metadata(#{storage_account_name}, #{container_name}, #{blob_name}, #{metadata})")
      _initialize_blob_client(storage_account_name) do
        begin
          options = merge_storage_common_options
          @logger.info("set_blob_metadata: Calling set_blob_metadata(#{container_name}, #{blob_name}, #{metadata}, #{options})")
          @blob_service_client.set_blob_metadata(container_name, blob_name, encode_metadata(metadata), options)
        rescue StandardError => e
          cloud_error("set_blob_metadata: Failed to set the metadata for the blob: inspect:#{e.inspect}\nbacktrace:#{e.backtrace.join("\n")}")
        end
      end
    end

    def list_blobs(storage_account_name, container_name, prefix = nil)
      @logger.info("list_blobs(#{storage_account_name}, #{container_name})")
      blobs = []
      _initialize_blob_client(storage_account_name) do
        options = {}
        options[:prefix] = prefix unless prefix.nil?
        loop do
          options = merge_storage_common_options(options)
          @logger.info("list_blobs: Calling list_blobs(#{container_name}, #{options})")
          temp = @blob_service_client.list_blobs(container_name, options)
          # Workaround for the issue https://github.com/Azure/azure-storage-ruby/issues/37
          raise temp unless temp.instance_of?(Azure::Service::EnumerationResults)

          blobs += temp unless temp.empty?
          break if temp.continuation_token.nil? || temp.continuation_token.empty?
          options[:marker] = temp.continuation_token
        end
      end
      blobs
    end

    def snapshot_blob(storage_account_name, container_name, blob_name, metadata)
      @logger.info("snapshot_blob(#{storage_account_name}, #{container_name}, #{blob_name}, #{metadata})")
      _initialize_blob_client(storage_account_name) do
        options = {
          metadata: metadata
        }
        options = merge_storage_common_options(options)
        @logger.info("snapshot_blob: Calling create_blob_snapshot(#{container_name}, #{blob_name}, #{options})")
        snapshot_time = @blob_service_client.create_blob_snapshot(container_name, blob_name, options)
        @logger.debug("snapshot_blob: Snapshot time: #{snapshot_time}")
        snapshot_time
      end
    end

    def copy_blob(storage_account_name, container_name, blob_name, source_blob_uri)
      @logger.info("copy_blob(#{storage_account_name}, #{container_name}, #{blob_name}, #{source_blob_uri})")
      _initialize_blob_client(storage_account_name) do
        begin
          start_time = Time.new
          options = merge_storage_common_options
          @logger.info("copy_blob: Calling copy_blob_from_uri(#{container_name}, #{blob_name}, #{source_blob_uri}, #{options})")
          copy_id, copy_status = @blob_service_client.copy_blob_from_uri(container_name, blob_name, source_blob_uri, options)
          @logger.info("copy_blob: x-ms-copy-id: #{copy_id}, x-ms-copy-status: #{copy_status}")

          copy_status_description = ''
          while copy_status == 'pending'
            options = merge_storage_common_options
            @logger.info("copy_blob: Calling get_blob_properties(#{container_name}, #{blob_name}, #{options})")
            blob = @blob_service_client.get_blob_properties(container_name, blob_name, options)
            blob_props = blob.properties
            cloud_error("copy_blob: The progress of copying the blob #{source_blob_uri} to #{container_name}/#{blob_name} was interrupted by other copy operations.") if !copy_id.nil? && blob_props[:copy_id] != copy_id

            copy_status_description = blob_props[:copy_status_description]
            copy_status = blob_props[:copy_status]
            break if copy_status != 'pending'

            @logger.debug("copy_blob: Copying progress: #{blob_props[:copy_progress]}")
            elapse_time = Time.new - start_time
            copied_bytes, total_bytes = blob_props[:copy_progress].split('/').map(&:to_i)
            interval = copied_bytes.zero? ? 5 : (total_bytes - copied_bytes).to_f / copied_bytes * elapse_time
            interval = 30 if interval > 30
            interval = 1 if interval < 1
            sleep(interval)
          end

          if copy_status == 'success'
            duration = Time.new - start_time
            @logger.info("copy_blob: Copy the blob #{source_blob_uri} successfully. Duration: #{duration.inspect}")
          else
            cloud_error("copy_blob: Failed to copy the blob #{source_blob_uri}: \n\tcopy status: #{copy_status}\n\tcopy description: #{copy_status_description}")
          end
        rescue StandardError => e
          ignore_exception do
            options = merge_storage_common_options
            @logger.info("copy_blob: Calling delete_blob(#{container_name}, #{blob_name}, #{options})")
            @blob_service_client.delete_blob(container_name, blob_name, options)
            @logger.info("copy_blob: Delete the blob #{container_name}/#{blob_name}")
          end
          raise e
        end
      end
    end

    private

    def _upload_page_blob(container_name, blob_name, file_path, thread_num)
      @logger.info("_upload_page_blob(#{container_name}, #{blob_name}, #{file_path}, #{thread_num})")
      start_time = Time.new
      file_size = File.lstat(file_path).size
      _upload_page_blob_in_threads(file_path, file_size, container_name, blob_name, thread_num)
      duration = Time.new - start_time
      @logger.info("_upload_page_blob_in_threads Duration: #{duration.inspect}")
    end

    def _initialize_blob_client(storage_account_name, disable_debug_mode = false)
      @blob_client_mutex.synchronize do
        unless @storage_accounts.key?(storage_account_name)
          storage_account = @azure_client.get_storage_account_by_name(storage_account_name)
          cloud_error("_initialize_blob_client: Storage account '#{storage_account_name}' not found") if storage_account.nil?
          keys = @azure_client.get_storage_account_keys_by_name(storage_account_name)
          storage_account[:key] = keys[0]
          @storage_accounts[storage_account_name] = storage_account
        end
        @azure_storage_client = initialize_azure_storage_client(@storage_accounts[storage_account_name], @azure_config)
        @blob_service_client = @azure_storage_client.blob_client
        @blob_service_client.with_filter(CustomizedRetryPolicyFilter.new)
        @blob_service_client.with_filter(Azure::Core::Http::DebugFilter.new) if is_debug_mode(@azure_config) && !disable_debug_mode
        yield
      end
    end

    def _compute_chunks(file_size, max_chunk_size)
      chunks = ChunkList.new
      offset = 0
      while offset < file_size
        chunk_size = offset + max_chunk_size > file_size ? file_size - offset : max_chunk_size
        chunks.push(Chunk.new(chunks.size + 1, offset, chunk_size))
        offset += max_chunk_size
      end
      chunks
    end

    def _upload_page_blob_in_threads(file_path, file_size, container_name, blob_name, thread_num)
      chunks = _compute_chunks(file_size, MAX_CHUNK_SIZE)
      options = {
        timeout: TIMEOUT_FOR_BLOB_OPERATIONS
      }
      standard_errors = Concurrent::Array.new
      threads = []
      thread_num.times do |id|
        thread = Thread.new do
          File.open(file_path, 'rb') do |file|
            while chunk = chunks.shift
              content = chunk.read(file)
              if content == @empty_chunk_content
                @logger.debug("_upload_page_blob_in_threads: Thread #{id}: Skip empty chunk: #{chunk}")
                next
              end

              retry_count = 0
              begin
                options = merge_storage_common_options(options)
                # Do not log content because it is too large.
                @logger.debug("_upload_page_blob_in_threads: Thread #{id}, retry: #{retry_count}, chunk id: #{chunk.id}: Calling put_blob_pages(#{container_name}, #{blob_name}, #{chunk.start_range}, #{chunk.end_range}, [CONTENT], #{options})")
                @blob_service_client.put_blob_pages(container_name, blob_name, chunk.start_range, chunk.end_range, content, options)
              rescue StandardError => e
                @logger.warn("_upload_page_blob_in_threads: Thread #{id}: Failed to put_blob_pages, error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                retry_count += 1
                if retry_count > AZURE_MAX_RETRY_COUNT
                  # make sure that other threads exit after they finish current job.
                  chunks.clear!
                  standard_errors.push(e)
                  break
                end
                sleep(10)
                retry
              end
            end
          end
        end
        thread.abort_on_exception = true
        threads << thread
      end
      threads.each(&:join)
      cloud_error(standard_errors.to_s) unless standard_errors.empty?
    end

    def _create_page_blob(container_name, blob_name, file_size, options)
      options = merge_storage_common_options(options)
      @blob_service_client.create_page_blob(container_name, blob_name, file_size, options)
    rescue StandardError => e
      if e.inspect.include?('ContainerNotFound')
        @blob_service_client.create_container(container_name, merge_storage_common_options)
        @blob_service_client.create_page_blob(container_name, blob_name, file_size, options)
      else
        raise e
      end
    end
  end

  private

  class ChunkList
    def initialize(chunks = [])
      @chunks = chunks
      @mutex = Mutex.new
    end

    def push(chunk)
      @mutex.synchronize { @chunks.push(chunk) }
    end

    def shift
      @mutex.synchronize { @chunks.shift }
    end

    def clear!
      @mutex.synchronize { @chunks.clear }
    end

    def size
      @mutex.synchronize { @chunks.size }
    end
  end

  class Chunk
    def initialize(id, offset, size)
      @id = id
      @offset = offset
      @size = size
    end

    attr_reader :id

    def start_range
      @offset
    end

    def end_range
      @offset + @size - 1
    end

    def read(file)
      file.seek(@offset)
      file.read(@size)
    end

    def to_s
      "id: #{@id}, offset: #{@offset}, size: #{@size}"
    end
  end

  class CustomizedRetryPolicyFilter < Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter
    def initialize(retry_count = nil, min_retry_interval = nil, max_retry_interval = nil)
      super(retry_count, min_retry_interval, max_retry_interval)
    end

    # Overrides the base class implementation of call to determine
    # how the HTTP request should continue retrying
    #
    # retry_data - Hash. Stores stateful retry data
    #
    # The retry_data is a Hash which can be used to store
    # stateful data about the request execution context (such as an
    # incrementing counter, timestamp, etc). The retry_data object
    # will be the same instance throughout the lifetime of the request
    def apply_retry_policy(retry_data)
      super(retry_data)

      if retry_data[:error].is_a?(OpenSSL::SSL::SSLError) || retry_data[:error].is_a?(OpenSSL::X509::StoreError)
        error_message = retry_data[:error].inspect

        if error_message.include?(Bosh::AzureCloud::Helpers::ERROR_OPENSSL_RESET)
          # Retry on "Connection reset by peer - SSL_connect" error (OpenSSL::SSL::SSLError, OpenSSL::X509::StoreError)
          # https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/234
          retry_data[:retryable] = true
        end
      end
    end
  end
end
