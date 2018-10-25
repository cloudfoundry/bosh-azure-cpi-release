# frozen_string_literal: true

# The following default configurations are shared. If one case needs a specific configuration, it should overwrite it.
shared_context 'shared stuff for azure client' do
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config
    )
  end

  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_compute) { AZURE_RESOURCE_PROVIDER_COMPUTE }
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:group_api_version) { AZURE_RESOURCE_PROVIDER_GROUP }
  let(:token_api_version) { AZURE_API_VERSION }
  let(:resource_group) { mock_azure_config.resource_group_name }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  let(:vmss_name) { 'fake_vmss_name' }
  let(:vmss_instance_id) { '0' }
  let(:disk_id) { 'fake-disk-id' }
  let(:disk_name) { 'fake-disk-name' }
end
