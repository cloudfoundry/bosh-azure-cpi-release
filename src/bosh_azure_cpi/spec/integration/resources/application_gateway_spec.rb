# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @application_gateway_name = ENV.fetch('BOSH_AZURE_APPLICATION_GATEWAY_NAME')
  end

  context 'when single application_gateway is specified in resource pool' do
    let(:network_spec) do
      {
        'network_a' => {
          'type' => 'manual',
          'ip' => "10.0.0.#{Random.rand(10..99)}",
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @subnet_name
          }
        }
      }
    end

    let(:vm_properties) do
      {
        'instance_type' => @instance_type,
        'application_gateway' => @application_gateway_name
      }
    end

    let(:threads) { 2 }
    let(:ip_address_start) do
      Random.rand(10..(100 - threads))
    end
    let(:ip_address_end) do
      ip_address_start + threads - 1
    end
    let(:ip_address_specs) do
      (ip_address_start..ip_address_end).to_a.collect { |x| "10.0.0.#{x}" }
    end
    let(:network_specs) do
      ip_address_specs.collect do |ip_address_spec|
        {
          'network_a' => {
            'type' => 'manual',
            'ip' => ip_address_spec,
            'cloud_properties' => {
              'virtual_network_name' => @vnet_name,
              'subnet_name' => @subnet_name
            }
          }
        }
      end
    end

    it 'should add the VM to the backend pool of application gateway' do
      ag_url = get_azure_client.rest_api_url(
        Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_NETWORK,
        Bosh::AzureCloud::AzureClient::REST_API_APPLICATION_GATEWAYS,
        name: @application_gateway_name
      )

      lifecycles = []
      threads.times do |i|
        lifecycles[i] = Thread.new do
          agent_id = SecureRandom.uuid
          ip_config_id = "/subscriptions/#{@subscription_id}/resourceGroups/#{@default_resource_group_name}/providers/Microsoft.Network/networkInterfaces/#{agent_id}-0/ipConfigurations/ipconfig0"
          begin
            new_instance_id = @cpi.create_vm(
              agent_id,
              @stemcell_id,
              vm_properties,
              network_specs[i]
            )
            ag = get_azure_client.get_resource_by_id(ag_url)
            expect(ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations']).to include(
              'id' => ip_config_id
            )
          ensure
            @cpi.delete_vm(new_instance_id) if new_instance_id
          end
          ag = get_azure_client.get_resource_by_id(ag_url)
          unless ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations'].nil?
            expect(ag['properties']['backendAddressPools'][0]['properties']['backendIPConfigurations']).not_to include(
              'id' => ip_config_id
            )
          end
        end
      end
      lifecycles.each(&:join)
    end
  end
end
