# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::Network do
  let(:azure_config) { mock_azure_config }
  let(:network_name) { 'fake-name' }

  describe '#initialize' do
    context 'when spec is invalid' do
      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::Network.new(azure_config, network_name, nil)
        end.to raise_error(/Invalid spec, Hash expected/)
      end
    end

    context 'when resource_group_name is specified in network spec' do
      let(:network_spec) do
        {
          'ip' => 'fake-ip',
          'default' => %w[dns gateway],
          'dns' => '8.8.8.8',
          'cloud_properties' => {
            'virtual_network_name' => 'foo',
            'subnet_name' => 'bar',
            'resource_group_name' => 'fake_resource_group',
            'security_group' => 'fake_sg'
          }
        }
      end

      it 'should return the resource group name' do
        network = Bosh::AzureCloud::Network.new(azure_config, network_name, network_spec)
        expect(network.resource_group_name).to eq('fake_resource_group')
      end
    end

    context 'when resource_group_name is not specified in network spec' do
      let(:network_spec) do
        {
          'ip' => 'fake-ip',
          'default' => %w[dns gateway],
          'dns' => '8.8.8.8',
          'cloud_properties' => {
            'virtual_network_name' => 'foo',
            'subnet_name' => 'bar',
            'security_group' => 'fake_sg'
          }
        }
      end

      it 'should return the resource group name' do
        network = Bosh::AzureCloud::Network.new(azure_config, network_name, network_spec)
        expect(network.resource_group_name).to eq(MOCK_RESOURCE_GROUP_NAME)
      end
    end
  end

  describe '#spec' do
    let(:network_spec) do
      {
        'ip' => 'fake-ip',
        'default' => %w[dns gateway],
        'dns' => '8.8.8.8',
        'cloud_properties' => {
          'virtual_network_name' => 'foo',
          'subnet_name' => 'bar',
          'resource_group_name' => 'fake_resource_group',
          'security_group' => 'fake_sg'
        }
      }
    end

    it 'should return the network spec' do
      network = Bosh::AzureCloud::Network.new(azure_config, network_name, network_spec)
      expect(network.spec).to eq(network_spec)
    end
  end
end
