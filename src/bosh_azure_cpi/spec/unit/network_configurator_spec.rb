# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::NetworkConfigurator do
  let(:azure_properties) { mock_azure_properties }
  let(:dynamic) do
    {
      'type' => 'dynamic',
      'default' => %w[dns gateway],
      'dns' => ['8.8.8.8'],
      'cloud_properties' =>
        {
          'subnet_name' => 'bar',
          'virtual_network_name' => 'foo'
        }
    }
  end
  let(:manual) do
    {
      'type' => 'manual',
      'dns' => ['9.9.9.9'],
      'ip' => 'fake-ip',
      'cloud_properties' =>
        {
          'resource_group_name' => 'fake-rg',
          'subnet_name' => 'bar',
          'virtual_network_name' => 'foo',
          'security_group' => 'fake-nsg'
        }
    }
  end
  let(:vip) do
    {
      'type' => 'vip'
    }
  end

  context "when spec isn't a hash" do
    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::NetworkConfigurator.new('foo')
      end.to raise_error ArgumentError
    end
  end

  context 'when network type is manual' do
    let(:network_spec) do
      {
        'network1' => manual
      }
    end

    it 'should create a ManualNetwork instance' do
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      expect(nc.networks.length).to eq(1)
      expect(nc.networks[0]).to be_a Bosh::AzureCloud::ManualNetwork
    end
  end

  context 'when network type is dynamic' do
    let(:network_spec) do
      {
        'network1' => dynamic
      }
    end

    it 'should create a DynamicNetwork instance' do
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      expect(nc.networks.length).to eq(1)
      expect(nc.networks[0]).to be_a Bosh::AzureCloud::DynamicNetwork
    end
  end

  context 'when network has vip configured' do
    let(:network_spec) do
      {
        'network1' => manual,
        'network2' => vip
      }
    end

    it 'should create a VipNetwork instance' do
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      expect(nc.vip_network).to be_a Bosh::AzureCloud::VipNetwork
      expect(nc.networks.length).to eq(1)
    end
  end

  context 'when network spec has 2 networks (dynamic and manual) defined' do
    let(:network_spec) do
      {
        'network1' => dynamic,
        'network2' => manual
      }
    end

    it 'should return 2 for length of @networks' do
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      expect(nc.networks.length).to eq(2)
    end
  end

  context 'when neither dynamic nor manual network is defined' do
    let(:network_spec) do
      {
        'network1' => vip
      }
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      end.to raise_error Bosh::Clouds::CloudError, 'At least one dynamic or manual network must be defined'
    end
  end

  context 'when multiple vip networks are defined' do
    let(:network_spec) do
      {
        'network1' => vip,
        'network2' => vip
      }
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      end.to raise_error Bosh::Clouds::CloudError, "More than one vip network for 'network2'"
    end
  end

  context 'when an illegal network type is used' do
    let(:network_spec) do
      {
        'network1' => { 'type' => 'foo' }
      }
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
      end.to raise_error Bosh::Clouds::CloudError, "Invalid network type 'foo' for Azure, " \
                        "can only handle 'dynamic', 'vip', or 'manual' network types"
    end
  end

  describe '#default_dns' do
    context 'when there are multiple networks' do
      let(:network_spec) do
        {
          'network1' => manual,
          'network2' => dynamic
        }
      end

      it 'should return dns from the network which has default dns defined' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
        expect(nc.default_dns).to eq(['8.8.8.8'])
      end
    end

    context 'when there is only 1 network' do
      let(:network_spec) do
        {
          'network1' => manual
        }
      end

      it 'should return dns from the network anyway' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_properties, network_spec)
        expect(nc.default_dns).to eq(['9.9.9.9'])
      end
    end
  end
end
