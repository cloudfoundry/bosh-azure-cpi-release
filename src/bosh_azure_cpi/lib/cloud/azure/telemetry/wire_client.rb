# frozen_string_literal: true

module Bosh::AzureCloud
  class RetriableError < RuntimeError; end

  class WireClient
    TELEMETRY_URI_FORMAT = 'http://%{endpoint}/machine?comp=telemetrydata'
    TELEMETRY_HEADER     = { 'Content-Type' => 'text/xml;charset=utf-8', 'x-ms-version' => '2012-11-30' }.freeze

    RETRY_ERROR_CODES    = [408, 429, 500, 502, 503, 504].freeze
    SLEEP_BEFORE_RETRY   = 5

    HEADER_LEASE         = 'lease {'
    HEADER_OPTION        = 'option unknown-245'
    HEADER_DNS           = 'option domain-name-servers'
    HEADER_EXPIRE        = 'expire'
    FOOTER_LEASE         = '}'

    LEASE_PATHS = {
      'Ubuntu' => '/var/lib/dhcp/dhclient.*.leases',
      'CentOS' => '/var/lib/dhclient/dhclient-*.leases'
    }.freeze

    def initialize(logger)
      @logger = logger
    end

    # Post data to wireserver
    #
    # @param [TelemetryEventList] event_list - events to be sent
    #
    def post_data(event_list)
      endpoint = get_endpoint

      if endpoint.nil?
        @logger.warn('[Telemetry] Wire server endpoint is nil, drop data')
      else
        uri = URI.parse(format(TELEMETRY_URI_FORMAT, endpoint: endpoint))
        retried = false
        begin
          request = Net::HTTP::Post.new(uri)
          request.body = event_list.format_data_for_wire_server
          TELEMETRY_HEADER.each_key do |key|
            request[key] = TELEMETRY_HEADER[key]
          end
          res = Net::HTTP.new(uri.host, uri.port, nil).start { |http| http.request request }

          status_code = res.code.to_i
          if status_code == 200
            @logger.debug("[Telemetry] Data posted: #{event_list.length} event(s)")
          elsif RETRY_ERROR_CODES.include?(status_code)
            raise RetriableError, "POST response - code: #{res.code}\nbody:#{res.body}"
          else
            raise "Failed to POST request. Response - code: #{res.code}\nbody:#{res.body}"
          end
        rescue RetriableError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
          if !retried
            retried = true
            sleep(SLEEP_BEFORE_RETRY)
            @logger.debug('[Telemetry] Failed to post data, retrying...')
            retry
          else
            @logger.warn("[Telemetry] Failed to post data to uri '#{uri}'. Error: \n#{e.inspect}\n#{e.backtrace.join("\n")}")
          end
        rescue StandardError => e
          @logger.warn("[Telemetry] Failed to post data to uri '#{uri}'. Error: \n#{e.inspect}\n#{e.backtrace.join("\n")}")
        end
      end
    end

    private

    # Get endpoint for different OS, only Ubuntu and CentOS are supported.
    #
    def get_endpoint
      os = nil
      endpoint = nil
      if File.exist?('/etc/lsb-release')
        os = 'Ubuntu' if File.read('/etc/lsb-release').include?('Ubuntu')
      elsif File.exist?('/etc/centos-release')
        os = 'CentOS' if File.read('/etc/centos-release').include?('CentOS')
      end
      endpoint = get_endpoint_from_leases_path(LEASE_PATHS[os]) unless os.nil?
      endpoint
    end

    # Try to discover and decode the wireserver endpoint in the specified dhcp leases path.
    #
    # @param [String] leases_path -  The path containing dhcp lease files
    # @return [String]            -  The endpoint if available, otherwise nil
    #
    def get_endpoint_from_leases_path(leases_path)
      lease_files = Dir.glob(leases_path)
      lease_files.each do |file_name|
        is_lease_file = false
        endpoint = nil
        expired  = true

        file = File.open(file_name, 'r')
        file.each_line do |line|
          case line
          when /#{HEADER_LEASE}/
            is_lease_file = true
          when /#{HEADER_OPTION}/
            # example - option unknown-245 a8:3f:81:10;
            endpoint = get_ip_from_lease_value(line.gsub(HEADER_OPTION, '').delete(';').strip)
          when /#{HEADER_EXPIRE}/
            # example - expire 1 2018/01/29 04:45:46;
            if line.include?('never')
              expired = false
            else
              begin
                ret = line.match('.*expire (\d*) (.*);')
                expire_date = ret[2]
                expired = false if Time.parse(expire_date) > Time.new
              rescue StandardError => e
                @logger.warn("[Telemetry] Failed to get expired data for leases of endpoint. Error:\n#{e.inspect}\n#{e.backtrace.join("\n")}")
              end
            end
          when /#{FOOTER_LEASE}/
            return endpoint if is_lease_file && !endpoint.nil? && !expired
          end
        end
      end

      @logger.warn("Can't find endpoint from leases_path '#{leases_path}'")
      nil
    end

    # example: a8:3f:81:10 -> 168.63.129.16
    def get_ip_from_lease_value(fallback_lease_value)
      unescaped_value = fallback_lease_value.delete('\\')
      return unless unescaped_value.length > 4

      unescaped_value.split(':').map(&:hex).join('.')
    end
  end
end
