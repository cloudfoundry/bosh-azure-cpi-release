require 'spec_helper'

describe Bosh::AzureCloud::BoshAgentUtil do

  subject(:agent_util) { described_class.new(uses_registry) }

  let(:registry_endpoint) { 'http://fake-registry.url/' }
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
    allow(config).to receive(:agent).and_return({'mbus' => 'http://u:p@somewhere'})
  end

  describe '#user_data_obj' do
    context 'when using registry' do
      let(:uses_registry) { true }
      let(:expected_user_data) do
        {
            registry: { endpoint: registry_endpoint },
            server: { name: instance_id },
            dns: { nameserver: dns }
        }
      end

      it 'user data is for registry usage' do
        user_data = agent_util.user_data_obj(
          registry_endpoint,
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

    context 'when not using registry' do
      let(:uses_registry) { false }
      let(:expected_user_data) do
        {
          server: { name: instance_id },
          dns: { nameserver: dns },
          'vm' => {'name' => vm_params[:name]},
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
              'lun' => "0",
              'host_device_id' => '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}',
            }
          },
          'env' => environment,
          'mbus' => 'http://u:p@somewhere',
        }
      end

      it 'combines the reduced vm metadata with agent settings and removes registry' do
        user_data = agent_util.user_data_obj(
          registry_endpoint,
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
  end
end