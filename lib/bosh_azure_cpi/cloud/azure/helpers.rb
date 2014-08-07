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

    # TODO: Move to stemcell creator
    def imageize_vhd(service_name, deployment_name, vm_name)
      # TODO: Need to set body
      # See: http://msdn.microsoft.com/en-us/library/azure/dn499768.aspx
      handle_response post("/#{Azure.subscription_id}/services/hostedservices/#{service_name}/" \
                           "deployments/#{deployment_name}/roleinstances/#{vm_name}/Operations")
    end

    private

    def handle_response(response)
      nil
    end

    def post(path, body=nil)
      http = Net::HTTP.new('management.core.windows.net', 443)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.add_field('x-ms-version', '2014-02-01')


      # TODO: Need to set body
      store = OpenSSL::X509::Store.new
      store.set_default_paths # Optional method that will auto-include the system CAs.
      store.add_cert(Azure.management_certificate)
      http.cert_store = store

      response = http.request(Net::HTTP::Post.new(path))
    end
  end
end