# frozen_string_literal: true

module Bosh::AzureCloud
  class TelemetryManager
    include Helpers

    EVENT_ID = '1'
    PROVIDER_ID = '69B669B9-4AF8-4C50-BDC4-6006FA76E975'
    CPI_TELEMETRY_NAME = 'BOSH-CPI'

    def initialize(azure_config)
      @azure_config = azure_config
      @logger = Bosh::Cpi::Logger.new(CPI_TELEMETRY_LOG_FILE)
    end

    # Monitor the status of a block
    # @param [String] operation - Operation name
    # @param [String] id        - ID. This value can be instance_id, disk_id, and so on. Using the id to avoid the events being aggregated by Kusto.
    # @param [Hash] extras      - Extra values passed by individual function. The values will be merged to 'message' column of the event.
    #                             Example:  {"instance_type" => "Standard_D1"}
    # @return - return value of the block
    #
    def monitor(operation, id: '', extras: {})
      if @azure_config.fetch('enable_telemetry', false) == true && @azure_config['environment'] != ENVIRONMENT_AZURESTACK
        error_raised = false

        event_param_name              = Bosh::AzureCloud::TelemetryEventParam.new('Name', CPI_TELEMETRY_NAME)
        event_param_version           = Bosh::AzureCloud::TelemetryEventParam.new('Version', Bosh::AzureCloud::VERSION)
        event_param_operation         = Bosh::AzureCloud::TelemetryEventParam.new('Operation', operation)
        event_param_container_id      = Bosh::AzureCloud::TelemetryEventParam.new('ContainerId', id)
        event_param_operation_success = Bosh::AzureCloud::TelemetryEventParam.new('OperationSuccess', true)
        event_param_message           = Bosh::AzureCloud::TelemetryEventParam.new('Message', '')
        event_param_duration          = Bosh::AzureCloud::TelemetryEventParam.new('Duration', 0)

        message_value = {
          'msg' => 'Successed',
          'subscription_id' => @azure_config['subscription_id']
        }
        message_value.merge!(extras)

        start_at = Time.now
        begin
          yield
        rescue StandardError => e
          error_raised = true

          event_param_operation_success.value = false
          msg = "#{e.inspect}\n#{e.backtrace.join("\n")}"
          msg = msg[0...3990] + '...' if msg.length > 3993 # limit the message to less than 3.9 kB
          message_value['msg'] = msg
          raise e
        ensure
          end_at = Time.now
          event_param_duration.value = (end_at - start_at) * 1000.0 # miliseconds
          event_param_message.value = message_value

          # No need to report event for "initialize" if it is initialized without an error
          unless operation == 'initialize' && !error_raised
            event = Bosh::AzureCloud::TelemetryEvent.new(EVENT_ID, PROVIDER_ID)
            event.add_param(event_param_name)
            event.add_param(event_param_version)
            event.add_param(event_param_operation)
            event.add_param(event_param_container_id)
            event.add_param(event_param_operation_success)
            event.add_param(event_param_message)
            event.add_param(event_param_duration)
            report_event(event)
          end
        end
      else
        yield
      end
    end

    private

    def report_event(event)
      filename = "/tmp/cpi-event-#{SecureRandom.uuid}.tld"
      File.open(filename, 'w') do |file|
        file.write(event.to_json)
      end
      FileUtils.mkdir_p(CPI_EVENTS_DIR)
      stdout, stderr, status = Open3.capture3("mv #{filename} #{CPI_EVENTS_DIR}")
      if status != 0
        @logger.warn("[Telemetry] Failed to move '#{filename}' to '#{CPI_EVENTS_DIR}', error: #{stderr}")
      else
        # trigger event handler to send the event in a different process
        fork do
          # create a new session and re-fork to make sure that exit of parent process won't kill the sub process.
          Process.setsid
          STDIN.reopen('/dev/null')
          STDOUT.reopen('/dev/null')
          STDERR.reopen(STDOUT)
          fork do
            Bosh::AzureCloud::TelemetryEventHandler.new(@logger).collect_and_send_events
          end
        end
      end
    rescue StandardError => e
      @logger.warn("[Telemetry] Failed to report event. Error:\n#{e.inspect}\n#{e.backtrace.join("\n")}")
    end
  end
end
