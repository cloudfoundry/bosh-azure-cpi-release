# frozen_string_literal: true

module Bosh::AzureCloud
  class CommandRunner
    def run_command(command, log_cmd = true)
      CPILogger.instance.logger.info(command) if log_cmd
      output, status = Open3.capture2e(command)
      raise Bosh::Clouds::CloudError, "'#{command}' failed with exit status=#{status.exitstatus} [#{output}]" if status.exitstatus != 0

      output
    end
  end
end
