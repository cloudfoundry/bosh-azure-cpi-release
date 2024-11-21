# frozen_string_literal: true

module Bosh::AzureCloud
  class TelemetryEventHandler
    include Helpers

    COOLDOWN = 60 # seconds

    def initialize(logger, events_dir = CPI_EVENTS_DIR)
      @logger = logger
      @events_dir = events_dir
      @wire_client = Bosh::AzureCloud::WireClient.new(logger)
    end

    # Collect events and send them to wireserver
    # Only one instance is allow to process the events at the same time.
    # Once this function get the lock, the instance will be responsible to handle all
    # existed event logs generated prior to and during the time when it handles the events;
    # Other instances won't get the lock and quit silently, their events will be handled
    # by the instance who got the lock.
    #
    def collect_and_send_events
      flock(CPI_LOCK_EVENT_HANDLER, File::LOCK_EX | File::LOCK_NB) do
        while has_event?
          last_post_timestamp = get_last_post_timestamp
          unless last_post_timestamp.nil?
            duration = Time.new.round - last_post_timestamp
            # will only send events once per minute
            sleep(COOLDOWN - duration) if duration >= 0 && duration < COOLDOWN
          end

          # sent_events
          event_list = collect_events
          send_events(event_list)
          update_last_post_timestamp(Time.new.round)
        end
      end
    end

    private

    # Check if there are events to be sent
    def has_event?
      event_files = Dir["#{@events_dir}/*.tld"]
      !event_files.empty?
    end

    # Collect telemetry events
    #
    # @params [Integer]  max - max event number to collect
    # @return [TelemetryEventList]
    #
    def collect_events(max = 4)
      event_list = []
      event_files = Dir["#{@events_dir}/*.tld"]
      event_files = event_files[0...max] if event_files.length > max
      event_files.each do |file|
        hash = JSON.parse(File.read(file))
        event_list << Bosh::AzureCloud::TelemetryEvent.parse_hash(hash)
      rescue StandardError => e
        @logger.warn("[Telemetry] Failed to collect event from '#{file}'. Error:\n#{e.inspect}\n#{e.backtrace.join("\n")}")
        raise e
      ensure
        File.delete(file)
      end
      Bosh::AzureCloud::TelemetryEventList.new(event_list)
    end

    # Send the events to wireserver
    #
    # @params [TelemetryEventList] event_list - events to be sent
    #
    def send_events(event_list)
      @wire_client.post_data(event_list)
    end

    # Get the time when the last post happened
    # Return Time or nil
    #
    def get_last_post_timestamp
      ignore_exception do
        Time.parse(File.read(CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP))
      end
    end

    # Record the time of last post in a file
    def update_last_post_timestamp(time)
      File.open(CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP, 'w') do |file|
        file.write(time.to_s)
      end
    end
  end
end
