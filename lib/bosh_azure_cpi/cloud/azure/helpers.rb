require 'yaml'
require 'azure'
require 'net/https'
require 'openssl'

module Bosh::AzureCloud
  module Helpers

    def vm_to_yaml(vm)
      raise 'Invalid vm object returned...' if not(validate(vm))
      { :vm_name => vm.vm_name, :cloud_service_name => vm.cloud_service_name }.to_yaml
    end

    def vm_from_yaml(yaml)
      symbolize_keys(YAML.load(yaml))
    end

    def symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        h
      end
    end

    private

    def validate(vm)
      return (!vm.nil? && !nil_or_empty?(vm.vm_name) && !nil_or_empty?(vm.cloud_service_name))
    end

    def nil_or_empty?(obj)
      return (obj.nil? || obj.empty?)
    end

    def handle_response(response)
      nil
    end

    def post(path, body=nil)
      store = OpenSSL::X509::Store.new
      store.set_default_paths # Optional method that will auto-include the system CAs.
      store.add_cert(OpenSSL::X509::Certificate.new(File.open(Azure.config.management_certificate)))

      request = Net::HTTP::Post.new(path)
      #
      # request.use_ssl = true
      # request.cert_store = store
      # request.verify_mode = OpenSSL::SSL::VERIFY_PEER
      request.add_field('x-ms-version', '2014-02-01')
      #
      request.content_type = 'text/xml'
      # request.body = body if not(body.nil?)
      #
      # response = nil
      # Net::HTTP.start('management.core.windows.net', 443) { |http|
      #   response = http.request(request)
      # }
      #
      # response

      http = Net::HTTP.new('management.core.windows.net', 443)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      #http.add_field('x-ms-version', '2014-02-01')

      #http.content_type = 'text/xml'
      #http.body = body if not(body.nil?)

      http.cert_store = store

      # response = http.request_post(path, { 'x-ms-version' => '2014-02-01', 'content-type' => 'text/xml' })
      response = http.request(request, body)

      response
    end
  end
end