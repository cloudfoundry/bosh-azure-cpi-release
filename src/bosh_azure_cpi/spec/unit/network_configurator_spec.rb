# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::NetworkConfigurator do
  let(:azure_config) { mock_azure_config }
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
        Bosh::AzureCloud::NetworkConfigurator.new(azure_config, 'cool')
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
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
      nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
        Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
        Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
        Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
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
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.default_dns).to eq(['9.9.9.9'])
      end
    end
  end

  describe '#nic_groups' do
    context 'when no nic_group is specified (backward compatibility)' do
      let(:network_spec) do
        {
          'network1' => {
            'type' => 'manual',
            'default' => %w[dns gateway],
            'ip' => '10.0.0.5',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar'
            }
          }
        }
      end

      it 'should create one nic_group per network (each network = its own NIC)' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.nic_groups.length).to eq(1)
        expect(nc.nic_groups[0].length).to eq(1)
        expect(nc.nic_groups[0][0].nic_group).to eq('network1')
      end
    end

    context 'when two networks have no nic_group (backward compatibility with multiple NICs)' do
      let(:network_spec) do
        {
          'network1' => {
            'type' => 'manual',
            'default' => %w[dns gateway],
            'ip' => '10.0.0.5',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar'
            }
          },
          'network2' => {
            'type' => 'manual',
            'ip' => '10.1.0.5',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'baz'
            }
          }
        }
      end

      it 'creates one nic_group per network and puts the primary network group first' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.nic_groups.map(&:length)).to eq([1, 1])
        expect(nc.nic_groups[0][0].nic_group).to eq('network1')
      end
    end

    context 'when two networks share the same nic_group (dual-stack)' do
      let(:network_spec) do
        {
          'ipv4' => {
            'type' => 'manual',
            'default' => %w[dns gateway],
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar'
            }
          },
          'ipv6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar-v6'
            }
          }
        }
      end

      it 'groups both networks into a single NIC group' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.nic_groups.length).to eq(1)
        expect(nc.nic_groups[0].map(&:private_ip)).to contain_exactly('10.0.0.5', 'fd00::5')
      end
    end

    context 'when networks are split across multiple nic_groups (multi-NIC dual-stack)' do
      let(:network_spec) do
        {
          'nic1-v4' => {
            'type' => 'manual',
            'default' => %w[dns gateway],
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar'
            }
          },
          'nic1-v6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar-v6'
            }
          },
          'nic2-v4' => {
            'type' => 'manual',
            'ip' => '10.1.0.5',
            'nic_group' => '2',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'baz'
            }
          }
        }
      end

      it 'creates two nic_groups, primary first, grouping networks sharing nic_group together' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.nic_groups.length).to eq(2)
        expect(nc.nic_groups[0].map(&:private_ip)).to contain_exactly('10.0.0.5', 'fd00::5')
        expect(nc.nic_groups[1].map(&:private_ip)).to contain_exactly('10.1.0.5')
      end
    end

    context 'when vip network is present alongside nic_groups' do
      let(:network_spec) do
        {
          'default' => {
            'type' => 'manual',
            'default' => %w[dns gateway],
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar'
            }
          },
          'v6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'foo',
              'subnet_name' => 'bar-v6'
            }
          },
          'public' => {
            'type' => 'vip'
          }
        }
      end

      it 'excludes the vip network and still groups the remaining networks correctly' do
        nc = Bosh::AzureCloud::NetworkConfigurator.new(azure_config, network_spec)
        expect(nc.nic_groups.length).to eq(1)
        expect(nc.nic_groups[0].length).to eq(2)
        expect(nc.nic_groups.flatten).to all(be_a(Bosh::AzureCloud::ManualNetwork))
      end
    end
  end
end
