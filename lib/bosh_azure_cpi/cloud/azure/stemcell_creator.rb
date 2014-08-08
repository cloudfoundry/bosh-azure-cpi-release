require_relative 'helpers'

module Bosh::AzureCloud
  class StemcellCreator
    include Bosh::Exec
    include Helpers

    # def initialize(cloud_service_client)
    #   @cloud_service_client = cloud_service_client
    # end

    def imageize_vhd(vm_id, deployment_name)
      vm = vm_from_yaml(vm_id)
      # TODO: Need to set body
      # See: http://msdn.microsoft.com/en-us/library/azure/dn499768.aspx
      handle_response post("/#{Azure.config.subscription_id}/services/hostedservices/#{vm[:cloud_service_name]}/" \
                           "deployments/#{deployment_name}/roleinstances/#{vm[:vm_name]}/Operations",
                           "<CaptureRoleAsVMImageOperation xmlns=\"http://schemas.microsoft.com/windowsazure\" xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">
                            <OperationType>CaptureRoleAsVMImageOperation</OperationType>
                            <OSState>Specialized</OSState>
                            <VMImageName>BOSH-Stemcell-#{(0..16).to_a.map{rand(16).to_s(16)}.join}</VMImageName>
                            <VMImageLabel>BOSH-Stemcell</VMImageLabel>
                            <Description>Auto created by BOSH on #{Time.now}</Description>
                            <Language>en-us</Language>
                          </CaptureRoleAsVMImageOperation>")
    end
  end
end