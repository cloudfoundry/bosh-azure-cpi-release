require 'yaml'
require 'azure'
require 'net/https'
require 'uri'

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

    # TODO: Need to figure a way to upload cert to BOSH as it is needed locally on the BOSH instance
    def post(uri, body=nil)
      uri = URI.parse(uri)
      pem = File.read(Azure.config.management_certificate)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert = OpenSSL::X509::Certificate.new(pem)
      http.key = OpenSSL::PKey::RSA.new(pem)
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = body unless body.nil?
      request['x-ms-version'] = '2014-06-01'
      request['Content-Type'] = 'application/xml' unless body.nil?

      http.request(request)
    end
  end
end