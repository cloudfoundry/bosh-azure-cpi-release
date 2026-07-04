# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud, 'IPv6 dual-stack' do
  before(:all) do
    skip('Test case requires dual-stack subnet') unless @dual_stack_subnet_name
  end

  let(:dual_stack_ipv4) { "10.0.3.#{Random.rand(1..254)}" }
  let(:dual_stack_ipv6) { "fd00::a" }
  let(:vm_properties) do
    {
      'instance_type' => @instance_type
    }
  end

  context 'dual-stack with nic_group' do
    let(:network_spec) do
      {
        'network_v4' => {
          'type' => 'manual',
          'ip' => dual_stack_ipv4,
          'nic_group' => '1',
          'default' => %w[dns gateway],
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @dual_stack_subnet_name
          }
        },
        'network_v6' => {
          'type' => 'manual',
          'ip' => dual_stack_ipv6,
          'nic_group' => '1',
          'cloud_properties' => {
            'virtual_network_name' => @vnet_name,
            'subnet_name' => @dual_stack_subnet_name
          }
        }
      }
    end

    it 'should create a VM with a single dual-stack NIC (two ipConfigurations)' do
      vm_lifecycle do |instance_id|
        instance_id_obj = Bosh::AzureCloud::InstanceId.parse(instance_id, @azure_config.resource_group_name)
        azure_client = get_azure_client
        nics = azure_client.list_network_interfaces_by_keyword(
          @default_resource_group_name,
          instance_id_obj.vm_name
        )

        expect(nics.length).to eq(1), "Expected 1 NIC but got #{nics.length}"

        nic = nics.first
        ip_configs = nic[:ip_configurations]
        expect(ip_configs.length).to eq(2), "Expected 2 ipConfigurations but got #{ip_configs.length}"

        ip_versions = ip_configs.map { |c| c[:private_ip_address_version] }.sort
        expect(ip_versions).to eq(%w[IPv4 IPv6])

        ipv4_config = ip_configs.find { |c| c[:private_ip_address_version] == 'IPv4' }
        expect(ipv4_config[:private_ip]).to eq(dual_stack_ipv4)

        ipv6_config = ip_configs.find { |c| c[:private_ip_address_version] == 'IPv6' }
        expect(ipv6_config[:private_ip]).to eq(dual_stack_ipv6)
      end
    end
  end
end
