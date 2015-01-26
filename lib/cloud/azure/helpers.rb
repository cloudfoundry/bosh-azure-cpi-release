module Bosh::AzureCloud
  module Helpers

    def generate_instance_id(cloud_service_name, vm_name)
      instance_id = cloud_service_name + "&" + vm_name
    end

    def parse_instance_id(instance_id)
      cloud_service_name, vm_name = instance_id.split("&")
    end

    def symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        h
      end
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
    
    def xml_content(xml, key, default = '')
      content = default
      node = xml.at_css(key)
      content = node.text if node
      content
    end

    private

    def validate(vm)
      (!vm.nil? && !nil_or_empty?(vm.vm_name) && !nil_or_empty?(vm.cloud_service_name))
    end

    def nil_or_empty?(obj)
      (obj.nil? || obj.empty?)
    end

    def handle_response(response)
      ret = wait_for_completion(response)
      Nokogiri::XML(ret.body) unless ret.nil?
    end
    
    def init_url(uri)
      "#{Azure.config.management_endpoint}/#{Azure.config.subscription_id}/#{uri}"
    end

    def http_get(uri)
      url = URI.parse(init_url(uri))
      request = Net::HTTP::Get.new(url.request_uri)
      request['x-ms-version'] = '2014-06-01'
      request['Content-Length'] = 0

      http(url).request(request)
    end

    def http_post(uri, body=nil)
      url = URI.parse(init_url(uri))
      request = Net::HTTP::Post.new(url.request_uri)
      request.body = body unless body.nil?
      request['x-ms-version'] = '2014-06-01'
      request['Content-Type'] = 'application/xml' unless body.nil?

      http(url).request(request)
    end

    def http_delete(uri, body=nil)
      url = URI.parse(init_url(uri))
      request = Net::HTTP::Delete.new(url.request_uri)
      request.body = body unless body.nil?
      request['x-ms-version'] = '2014-06-01'
      request['Content-Type'] = 'application/xml' unless body.nil?

      http(url).request(request)
    end

    def http(url)
      pem = File.read(Azure.config.management_certificate)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.cert = OpenSSL::X509::Certificate.new(pem)
      http.key = OpenSSL::PKey::RSA.new(pem)
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http
    end
    
    def wait_for_completion(response)
      ret_val = Nokogiri::XML response.body
      if ret_val.at_css('Error Code') && ret_val.at_css('Error Code').content == 'AuthenticationFailed'
        cloud_error(ret_val.at_css('Error Code').content + ' : ' + ret_val.at_css('Error Message').content)
      end
      if response.code.to_i == 200 || response.code.to_i == 201
        return response
      elsif response.code.to_i == 307
        #rebuild_request response
        cloud_error("Currently bosh_azure_cpi does not support proxy.")
      elsif response.code.to_i > 201 && response.code.to_i <= 299
        check_completion(response['x-ms-request-id'])
      elsif warn && !response.success?
      elsif response.body
        if ret_val.at_css('Error Code') && ret_val.at_css('Error Message')
          cloud_error(ret_val.at_css('Error Code').content + ' : ' + ret_val.at_css('Error Message').content)
        else
          cloud_error(nil, "http error: #{response.code}")
        end
      else
        cloud_error(nil, "http error: #{response.code}")
      end
    end
    
    def check_completion(request_id)
      request_path = "/operations/#{request_id}"
      done = false
      while not done
        puts '# '
        response = http_get(request_path)
        ret_val = Nokogiri::XML response.body
        status = xml_content(ret_val, 'Operation Status')
        status_code = response.code.to_i
        if status != 'InProgress'
          done = true
        end
        if response.code.to_i == 307
          done = true
        end
        if done
          if status.downcase != 'succeeded'
            error_code = xml_content(ret_val, 'Operation Error Code')
            error_msg = xml_content(ret_val, 'Operation Error Message')
            cloud_error(nil, "#{error_code}: #{error_msg}")
          else
            puts "#{status.downcase} (#{status_code})"
          end
          return
        else
          sleep(5)
        end
      end
    end
  end
end