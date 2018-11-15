# frozen_string_literal: true

module Bosh::AzureCloud
  class Batching
    include Singleton
    include Helpers

    def execute(request, executor)
      FileUtils.mkdir_p(CPI_BATCH_TASK_DIR)
      CPILogger.instance.logger.info("executing #{request}")
      grouping_key = request[:grouping_key]

      task_in_file_path = _get_task_in_file_path(grouping_key)
      flock(_get_task_in_file_lock_name(grouping_key), File::LOCK_EX) do
        # TODO: check whether this is the current task in file
        # for the case that rebooting leave some garbage here.
        task_in_pipe = File.open(task_in_file_path, 'a+')
        task_text = "#{Base64.strict_encode64(request.to_json)}\n"
        CPILogger.instance.logger.info("writing #{task_text} to #{task_in_file_path}")
        task_in_pipe.write(task_text)
        task_in_pipe.close
      end

      # only one process can get into the real execution.
      _try_to_execute(request, executor)
      _wait_for_result(request)
    end

    private

    # grouping_key is somethink like the vmss_name.
    def _try_to_execute(request, executor)
      grouping_key = request[:grouping_key]
      task_in_file_path = _get_task_in_file_path(grouping_key)
      # handling the items int the fifo identified by grouping_key by executor.
      task_executor_lock_name = _get_task_executor_lock_name(grouping_key)
      sleep(3) # sleep 3 seconds to let the task file grow as big as possible.
      flock(task_executor_lock_name, File::LOCK_EX) do
        # read all the items in the task file
        flock(_get_task_in_file_lock_name(grouping_key), File::LOCK_EX) do
          if File.exist?(task_in_file_path)
            task_in_pipe = File.open(task_in_file_path, 'r')
            buckets = {}
            loop do
              break if task_in_pipe.eof?

              task_item_text = task_in_pipe.readline
              begin
                CPILogger.instance.logger.info("task item text is #{task_item_text}")
                decoded_text = Base64.strict_decode64(task_item_text.strip)
                task_obj = JSON.parse(decoded_text, symbolize_names: true)
                result_bucket_key = _get_result_bucket_key(task_obj[:params])
                # append the task item into the end
                if buckets[result_bucket_key].nil?
                  buckets[result_bucket_key] = {
                    req: task_obj[:params],
                    count: 1
                  }
                else
                  buckets[result_bucket_key][:count] = buckets[result_bucket_key][:count] + 1
                end
              rescue StandardError => e
                CPILogger.instance.logger.error("decoded_text: #{decoded_text} Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
                next
              end
            end

            # run the executor targeting the buckets.
            buckets.each do |result_bucket_key, v|
              CPILogger.instance.logger.info("executing bucket item with key: #{result_bucket_key} value: #{v}")
              results = executor.call(v[:req], v[:count])
              outputs_pipe_path = _get_task_outputs_directory_path(result_bucket_key)
              FileUtils.mkdir_p(outputs_pipe_path)
              flock(_get_task_outputs_file_lock_name(result_bucket_key), File::LOCK_EX) do
                results.each do |r|
                  result_item = "#{SecureRandom.uuid}.out"
                  result_item_file_path = File.join(outputs_pipe_path, result_item)
                  out_pipe = File.open(result_item_file_path, 'a+')
                  CPILogger.instance.logger.info("writing result item file #{result_item_file_path}")
                  out_pipe.write("#{Base64.strict_encode64(JSON.dump(r))}\n")
                  out_pipe.close
                end
              end
            end
            File.delete(task_in_file_path)
          else
            CPILogger.instance.logger.debug('no task in file available.')
          end
        end
      end
    end

    def _get_result_bucket_key(params)
      md = Digest::MD5.hexdigest(params.to_json)
      md.to_s
    end

    def _wait_for_result(request)
      # scan the result file.
      result_bucket_key = _get_result_bucket_key(request[:params])
      max_waiting_times = 30 * 60 / 3 # wait for max 30 minutes
      current_times = 0
      loop do
        CPILogger.instance.logger.debug("waiting for outputs with bucket key: #{result_bucket_key}")
        sleep(3)
        current_times += 1
        outputs_pipe_path = _get_task_outputs_directory_path(result_bucket_key)
        # puts Dir.exist?(outputs_pipe_path)
        # next unless Dir.exist?(outputs_pipe_path)
        break if current_times >= max_waiting_times

        flock(_get_task_outputs_file_lock_name(result_bucket_key), File::LOCK_EX) do
          items_in_folder = Dir["#{outputs_pipe_path}/*.out"].sort_by { |f| File.mtime(f) }
          if !items_in_folder.nil? && items_in_folder.length.positive?
            first_item = items_in_folder[items_in_folder.length - 1]
            content = File.read(first_item)
            CPILogger.instance.logger.info("got the result item #{first_item}")
            result_obj = JSON.parse(Base64.strict_decode64(content.strip), symbolize_names: true)
            File.delete(first_item)
            CPILogger.instance.logger.info("removed the result item #{first_item}")
            return result_obj
          end
        end
      end
    end

    def _get_task_in_file_path(grouping_key)
      "#{CPI_BATCH_TASK_DIR}/#{grouping_key}.tfin"
    end

    def _get_task_in_file_lock_name(grouping_key)
      "#{grouping_key}.tflock"
    end

    def _get_task_outputs_directory_path(outputs_key)
      "#{CPI_BATCH_TASK_DIR}/#{outputs_key}.out"
    end

    def _get_task_outputs_file_lock_name(outputs_key)
      "#{outputs_key}.out"
    end

    def _get_task_executor_lock_name(grouping_key)
      "#{grouping_key}.exlock"
    end
  end
end
