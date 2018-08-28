# frozen_string_literal: true

module Bosh::AzureCloud
  class CommandRunner
    def initialize
      @logger = Bosh::Clouds::Config.logger
    end

    def run_command(command, log_cmd = true)
      @logger.info(command) if log_cmd
      output, status = Open3.capture2e(command)
      raise Bosh::Clouds::CloudError, "'#{command}' failed with exit status=#{status.exitstatus} [#{output}]" if status.exitstatus != 0
    end
  end
end
