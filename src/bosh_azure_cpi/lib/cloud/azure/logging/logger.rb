# frozen_string_literal: true

module Bosh::AzureCloud
  class CPILogger
    include Singleton
    attr_accessor :logger

    def initialize
      @mutex = Mutex.new
      @mdc_mutex = Mutex.new
      @loggers = {}
    end

    def get_logger(device)
      if @loggers[device].nil?
        @mutex.synchronize do
          if @loggers[device].nil?
            logger = Logging.logger(
              device,
              pattern: '%.1l, [%d #%p #%t] %l --%X{flag}: %m\n', # flag is a placeholder for request id
              date_pattern: '%Y-%m-%dT%H:%M:%S.%6N'
            )
            logger.level = :debug
            @loggers[device] = logger
          end
        end
      end
      @loggers[device]
    end

    def set_request_id(id)
      # mapped diagnostic context
      @mdc_mutex.synchronize do
        Logging.mdc['flag'] = " [req_id #{id}]"
      end
    end
  end
end
