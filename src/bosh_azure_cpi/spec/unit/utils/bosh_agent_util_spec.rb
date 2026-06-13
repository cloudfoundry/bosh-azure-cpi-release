# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::BoshAgentUtil do
  subject(:agent_util) { Bosh::AzureCloud::BoshAgentUtil.new }

  let(:instance_id) { 'fake-instance-id' }
  let(:dns) { 'fake-dns' }
  let(:agent_id) { 'fake-agent-id' }
  let(:vm_params) do
    {
      name: 'vm_name',
      ephemeral_disk: {},
    }
  end
  let(:network_spec) do
    {
      'network_a' => {
        'type' => 'dynamic',
        'cloud_properties' => {
          'virtual_network_name' => 'vnet_name',
          'subnet_name' => 'subnet_name'
        }
      }
    }
  end
  let(:environment) { 'fake-agent-environment' }
  let(:config) { instance_double(Bosh::AzureCloud::Config) }
  let(:computer_name) { 'fake-computer-name' }

  before do
    allow(config).to receive(:agent).and_return({ 'mbus' => 'http://u:p@somewhere' })
  end

  describe '#user_data_obj' do
    let(:expected_user_data) do
      {
        server: { name: instance_id },
        dns: { nameserver: dns },
        'vm' => { 'name' => vm_params[:name] },
        'agent_id' => agent_id,
        'networks' => {
          'network_a' => {
            'type' => 'dynamic',
            'cloud_properties' => {
              'virtual_network_name' => 'vnet_name',
              'subnet_name' => 'subnet_name'
            },
            'use_dhcp' => true
          }
        },
        'disks' => {
          'system' => '/dev/sda',
          'persistent' => {},
          'ephemeral' => {
            'lun' => '0',
            'host_device_id' => '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}',
          }
        },
        'env' => environment,
        'mbus' => 'http://u:p@somewhere',
      }
    end

    it 'combines the reduced vm metadata with agent settings' do
      user_data = agent_util.user_data_obj(
        instance_id,
        dns,
        agent_id,
        network_spec,
        environment,
        vm_params,
        config,
      )

      expect(user_data).to eq(expected_user_data)
    end
  end

  describe '#user_data_obj — nic_group alias threading' do
    def networks_for(spec, nic_groups_to_iface = nil)
      args = [instance_id, dns, agent_id, spec, environment, vm_params, config]
      args.push(nil, nic_groups_to_iface) unless nic_groups_to_iface.nil?
      agent_util.user_data_obj(*args)['networks']
    end

    context 'when networks share a single nic_group (dual-stack)' do
      let(:dual_stack_spec) do
        {
          'default-ipv4' => {
            'type' => 'manual', 'ip' => '10.0.0.5', 'nic_group' => '1',
            'default' => %w[dns gateway],
            'cloud_properties' => { 'virtual_network_name' => 'boshvnet', 'subnet_name' => 'dual-stack-subnet' }
          },
          'default-ipv6' => {
            'type' => 'manual', 'ip' => 'fd00::5', 'nic_group' => '1',
            'cloud_properties' => { 'virtual_network_name' => 'boshvnet', 'subnet_name' => 'dual-stack-subnet' }
          }
        }
      end

      it 'sets the same alias on both networks, enables use_dhcp, and preserves other fields' do
        networks = networks_for(dual_stack_spec, '1' => 'eth0')

        expect(networks['default-ipv4']).to include('alias' => 'eth0', 'use_dhcp' => true, 'ip' => '10.0.0.5', 'type' => 'manual')
        expect(networks['default-ipv6']).to include('alias' => 'eth0', 'use_dhcp' => true, 'ip' => 'fd00::5')
      end
    end

    context 'when networks are split across multiple nic_groups (multi-NIC dual-stack)' do
      let(:multi_nic_spec) do
        {
          'net-v4-a' => { 'type' => 'manual', 'ip' => '10.0.0.5', 'nic_group' => '1', 'default' => %w[dns gateway], 'cloud_properties' => {} },
          'net-v6-a' => { 'type' => 'manual', 'ip' => 'fd00::5',  'nic_group' => '1', 'cloud_properties' => {} },
          'net-v4-b' => { 'type' => 'manual', 'ip' => '10.0.1.5', 'nic_group' => '2', 'cloud_properties' => {} },
          'net-v6-b' => { 'type' => 'manual', 'ip' => 'fd01::5',  'nic_group' => '2', 'cloud_properties' => {} }
        }
      end

      it 'maps each group to its assigned interface' do
        networks = networks_for(multi_nic_spec, '1' => 'eth0', '2' => 'eth1')
        aliases = networks.transform_values { |n| n['alias'] }

        expect(aliases).to eq(
          'net-v4-a' => 'eth0', 'net-v6-a' => 'eth0',
          'net-v4-b' => 'eth1', 'net-v6-b' => 'eth1'
        )
      end
    end

    context 'when only some networks have a nic_group' do
      let(:mixed_spec) do
        {
          'grouped-v4' => { 'type' => 'manual',  'ip' => '10.0.0.5', 'nic_group' => '1', 'cloud_properties' => {} },
          'grouped-v6' => { 'type' => 'manual',  'ip' => 'fd00::5',  'nic_group' => '1', 'cloud_properties' => {} },
          'ungrouped'  => { 'type' => 'dynamic', 'cloud_properties' => {} }
        }
      end

      it 'sets alias only on the grouped networks' do
        networks = networks_for(mixed_spec, '1' => 'eth0')

        expect(networks['grouped-v4']['alias']).to eq('eth0')
        expect(networks['grouped-v6']['alias']).to eq('eth0')
        expect(networks['ungrouped']).not_to have_key('alias')
      end
    end

    context 'backward compatibility: no nic_groups_to_iface' do
      it 'omits alias whether the argument is empty or absent, while still setting use_dhcp' do
        from_empty   = networks_for(network_spec, {})
        from_default = networks_for(network_spec)

        expect(from_empty['network_a']).not_to have_key('alias')
        expect(from_default['network_a']).not_to have_key('alias')
        expect(from_default['network_a']['use_dhcp']).to be true
      end
    end
  end
end
