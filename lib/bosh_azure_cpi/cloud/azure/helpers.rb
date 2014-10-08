require 'yaml'
require 'azure'
require 'net/https'
require 'uri'
require 'xmlsimple'

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
      (!vm.nil? && !nil_or_empty?(vm.vm_name) && !nil_or_empty?(vm.cloud_service_name))
    end

    def nil_or_empty?(obj)
      (obj.nil? || obj.empty?)
    end

    def handle_response(response)
      XmlSimple.xml_in(response.body) unless response.body.nil?
    end

    def get(uri)
      url = URI.parse(uri)
      request = Net::HTTP::Get.new(url.request_uri)
      request['x-ms-version'] = '2014-06-01'
      request['Content-Length'] = 0

      http(uri).request(request)
    end

    # TODO: Need to figure a way to upload cert to BOSH as it is needed locally on the BOSH instance
    def post(uri, body=nil)
      url = URI.parse(uri)
      request = Net::HTTP::Post.new(url.request_uri)
      request.body = body unless body.nil?
      request['x-ms-version'] = '2014-06-01'
      request['Content-Type'] = 'application/xml' unless body.nil?

      http(url).request(request)
    end

    def delete(uri, body=nil)
      url = URI.parse(uri)
      request = Net::HTTP::Delete.new(url.request_uri)
      request.body = body unless body.nil?
      request['x-ms-version'] = '2014-06-01'
      request['Content-Type'] = 'application/xml' unless body.nil?

      http(uri).request(request)
    end


    private

    def http(uri)
      url = URI.parse(uri)
      pem = File.read(Azure.config.management_certificate)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.cert = OpenSSL::X509::Certificate.new(pem)
      http.key = OpenSSL::PKey::RSA.new(pem)
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http
    end
  end
end