# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VipNetwork do
  let(:azure_config) { mock_azure_config }

  context 'with resource_group_name' do
    let(:network_spec) do
      {
        'type' => 'vip',
        'ip' => 'fake-vip',
        'cloud_properties' => {
          'resource_group_name' => 'foo'
        }
      }
    end

    it 'should get resource_group_name from cloud_properties' do
      nc = Bosh::AzureCloud::VipNetwork.new(azure_config, 'vip', network_spec)
      expect(nc.public_ip).to eq('fake-vip')
      expect(nc.resource_group_name).to eq('foo')
    end
  end

  context 'without resource_group_name' do
    let(:network_spec) do
      {
        'type' => 'vip',
        'ip' => 'fake-vip',
        'cloud_properties' => {}
      }
    end

    it 'should get resource_group_name from global azure properties' do
      nc = Bosh::AzureCloud::VipNetwork.new(azure_config, 'vip', network_spec)
      expect(nc.public_ip).to eq('fake-vip')
      expect(nc.resource_group_name).to eq(azure_config.resource_group_name)
    end
  end
end
