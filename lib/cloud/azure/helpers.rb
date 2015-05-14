module Bosh::AzureCloud
  module Helpers

    AZURE_ENVIRONMENTS = {
      'AzureCloud' => {
        'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254433',
        'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254432',
        'managementEndpointUrl' => 'https://management.core.windows.net',
        'resourceManagerEndpointUrl' => 'https://management.azure.com/',
        'sqlManagementEndpointUrl' => 'https://management.core.windows.net:8443/',
        'sqlServerHostnameSuffix' => '.database.windows.net',
        'galleryEndpointUrl' => 'https://gallery.azure.com/',
        'activeDirectoryEndpointUrl' => 'https://login.windows.net',
        'activeDirectoryResourceId' => 'https://management.core.windows.net/',
        'commonTenantName' => 'common',
        'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
        'activeDirectoryGraphApiVersion' => '2013-04-05'
      },
      'AzureChinaCloud' => {
        'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=301902',
        'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkID=301774',
        'managementEndpointUrl' => 'https://management.core.chinacloudapi.cn',
        'sqlManagementEndpointUrl' => 'https://management.core.chinacloudapi.cn:8443/',
        'sqlServerHostnameSuffix' => '.database.chinacloudapi.cn',
        'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
        'activeDirectoryResourceId' => 'https://management.core.chinacloudapi.cn/',
        'commonTenantName' => 'common',
        'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
        'activeDirectoryGraphApiVersion' => '2013-04-05'
      }
    }

    def generate_instance_id(resource_group_name, agent_id)
      instance_id = "bosh-#{resource_group_name}--#{agent_id}"
    end

    def parse_resource_group_from_instance_id(instance_id)
      index = instance_id.rindex('--') - 1
      instance_id[5..index]
    rescue
      cloud_error("Cannot parse resource group name from instance_id #{instance_id}. The format should be bosh-RESOURCEGROUPNAME--AGENTID")
    end

    def get_os_disk_name(instance_id)
      "#{instance_id}_os_disk"
    end

    ##
    # Raises CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [Exception] exception Exception to be logged (optional)
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    def azure_cmd(cmd)
      @logger.info("Execute command #{cmd}")

      exit_status = 0
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        exit_status = wait_thr.value
        if exit_status == 0
          @logger.debug("exit_status is: #{exit_status.to_s}")
          @logger.debug("stdout is: #{stdout.read}")
          @logger.debug("stderr is: #{stderr.read}")
        else
          @logger.info("Command failed. Please try it manually to see more details")
          @logger.error("exit_status is: #{exit_status.to_s}")
          @logger.error("stdout is: #{stdout.read}")
          @logger.error("stderr is: #{stderr.read}")
        end
      end

      exit_status
    end

    def invoke_azure_js(args, abort_on_error=false)
      node_js_file = File.join(File.dirname(__FILE__), "azure_crp", "azure_crp_compute.js")
      cmd = ["node", node_js_file]
      cmd.concat(args)
      @logger.info(cmd[2..-1].join(" ")[0..200])
      result = {}

      node_path = ENV['NODE_PATH']
      node_path = "/usr/local/lib/node_modules" if node_path.nil? or node_path.empty?
      node_env = {'NODE_PATH' => node_path}
    
      Open3.popen3(node_env, *cmd) { |stdin, stdout, stderr, wait_thr|
        data = ""
        stdstr = ""
        begin
          while wait_thr.alive? do
            IO.select([stdout])
            data = stdout.read_nonblock(1024000)
            @logger.info(data)
            stdstr += data
            task_checkpoint
          end
        rescue Errno::EAGAIN
          retry
        rescue EOFError
        end

        errstr = stderr.read
        stdstr += stdout.read
        if errstr and errstr.length > 0
          errstr = "\n\t\tPlease check if env NODE_PATH is correct\n#{errstr}"  if errstr=~/Function.Module._load/
          cloud_error(errstr)
        end

        matchdata = stdstr.match(/##RESULTBEGIN##(.*)##RESULTEND##/im)
        result = JSON(matchdata.captures[0]) if matchdata
        exitcode = wait_thr.value
        @logger.debug(result)

        unless result["Failed"].nil?
          cloud_error("AuthorizationFailed please try azure login\n") if result["Failed"]["code"] =~/AuthorizationFailed/
          cloud_error("Can't find token in ~/.azure/azureProfile.json or ~/.azure/accessTokens.json\nTry azure login\n") if result["Failed"]["code"] =~/RefreshToken Fail/
          cloud_error(result["Failed"])  if  abort_on_error
        end

       result["R"]

      }
    end

    def invoke_azure_js_with_id(arg)
      task = arg[0]
      instance_id = arg[1]

      begin
        resource_group_name = parse_resource_group_from_instance_id(instance_id)
        @logger.debug("resource_group_name is #{resource_group_name}")
        params = ["-t", task, "-r", resource_group_name, instance_id]
        params.concat(arg[2..-1])
        invoke_azure_js(params)
      rescue Exception => e
        cloud_error("Error: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    private

    def task_checkpoint
      Bosh::Clouds::Config.task_checkpoint
    end

  end
end
