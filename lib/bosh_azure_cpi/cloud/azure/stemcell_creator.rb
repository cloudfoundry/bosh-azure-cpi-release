require 'azure'
require_relative 'helpers'

module Bosh::AzureCloud
  class StemcellCreator
    include Bosh::Exec
    include Helpers


    # TODO: Need to set more predictable name in request as Azure returns an empty body... not sure why...
    def imageize_vhd(vm_id, deployment_name)
      vm = vm_from_yaml(vm_id)
      # TODO: Need to set body
      # See: http://msdn.microsoft.com/en-us/library/azure/dn499768.aspx
      handle_response post("https://management.core.windows.net/#{Azure.config.subscription_id}/" \
                           "services/hostedservices/#{vm[:cloud_service_name]}/deployments/" \
                           "#{deployment_name}/roleinstances/#{vm[:vm_name]}/Operations",
                           "<CaptureRoleAsVMImageOperation xmlns=\"http://schemas.microsoft.com/windowsazure\" " \
                           "xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" \
                           '<OperationType>CaptureRoleAsVMImageOperation</OperationType>' \
                           '<OSState>Specialized</OSState>' \
                           "<VMImageName>BOSH-Stemcell-#{(0..16).to_a.map{rand(16).to_s(16)}.join}</VMImageName>" \
                           '<VMImageLabel>BOSH-Stemcell</VMImageLabel>' \
                           "<Description>Auto created by BOSH on #{Time.now}</Description>" \
                           '</CaptureRoleAsVMImageOperation>')
    end
  end
end