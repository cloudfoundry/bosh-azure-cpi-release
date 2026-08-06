# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager, 'dual-stack NIC creation' do
  include_context 'shared stuff for vm manager'

  subject(:vm_manager_ds) { vm_manager2 }

  let(:dual_stack_subnet) { double('dual-stack-subnet', id: 'fake-dual-stack-subnet-id') }

  let(:manual_network_v4) { build_manual_network(private_ip: '10.0.0.5', subnet_name: 'dual-stack-subnet') }
  let(:manual_network_v6) { build_manual_network(private_ip: 'fd00::5',  subnet_name: 'dual-stack-subnet') }
  let(:interleaved_networks) do
    Array.new(17) do |index|
      private_ip = index.even? ? "10.0.0.#{index + 5}" : "fd00::#{index + 5}"
      build_manual_network(private_ip: private_ip, subnet_name: 'dual-stack-subnet')
    end
  end
  let(:dynamic_net) do
    instance_double(Bosh::AzureCloud::DynamicNetwork).tap do |n|
      allow(n).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
      allow(n).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
      allow(n).to receive(:subnet_name).and_return('fake-subnet-name')
      allow(n).to receive(:security_group).and_return(empty_security_group)
      allow(n).to receive(:application_security_groups).and_return([])
      allow(n).to receive(:ip_forwarding).and_return(false)
      allow(n).to receive(:accelerated_networking).and_return(false)
      allow(n).to receive(:nic_group).and_return('2')
    end
  end

  def build_manual_network(private_ip:, subnet_name:, nic_group: '1')
    instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
      allow(n).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
      allow(n).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
      allow(n).to receive(:subnet_name).and_return(subnet_name)
      allow(n).to receive(:private_ip).and_return(private_ip)
      allow(n).to receive(:security_group).and_return(empty_security_group)
      allow(n).to receive(:application_security_groups).and_return([])
      allow(n).to receive(:ip_forwarding).and_return(false)
      allow(n).to receive(:accelerated_networking).and_return(false)
      allow(n).to receive(:nic_group).and_return(nic_group)
    end
  end

  def capture_nic_params
    captured = []
    allow(azure_client).to receive(:create_network_interface) { |_rg, params| captured << params }
    vm_manager_ds.send(:_create_network_interfaces,
                       MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                       vm_props, network_configurator)
    captured.sort_by { |params| params[:name] }
  end

  before do
    allow(azure_client).to receive(:get_network_subnet_by_name)
      .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'dual-stack-subnet')
      .and_return(dual_stack_subnet)
    allow(azure_client).to receive(:get_network_subnet_by_name)
      .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'fake-subnet-name')
      .and_return(subnet)

    allow(network_configurator).to receive(:vip_network).and_return(nil)
    allow(azure_client).to receive(:list_public_ips).and_return([])
    allow(azure_client).to receive(:get_network_interface_by_name)
  end

  context 'when a single nic_group bundles an IPv4 and an IPv6 manual network' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v6, manual_network_v4]])
    end

    it 'creates the IPv4 ipConfiguration first regardless of network order' do
      nic_params_list = capture_nic_params

      expect(nic_params_list.length).to eq(1)

      nic = nic_params_list.first
      expect(nic[:name]).to eq("#{vm_name}-0")
      expect(nic[:ip_configurations]).to match([
        a_hash_including(name: 'ipconfig0-0', ip_version: 'IPv4', private_ip: '10.0.0.5', subnet: dual_stack_subnet),
        a_hash_including(name: 'ipconfig0-1', ip_version: 'IPv6', private_ip: 'fd00::5',  subnet: dual_stack_subnet)
      ])
    end
  end

  context 'when a nic_group contains multiple networks of the same IP family' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([interleaved_networks])
    end

    it 'keeps their relative order while placing IPv4 configurations before IPv6' do
      nic = capture_nic_params.first
      expected_ipv4 = (0...17).select(&:even?).map { |index| "10.0.0.#{index + 5}" }
      expected_ipv6 = (0...17).select(&:odd?).map { |index| "fd00::#{index + 5}" }

      expect(nic[:ip_configurations].map { |ipconfig| ipconfig[:private_ip] }).to eq(expected_ipv4 + expected_ipv6)
    end
  end

  context 'when there are multiple nic_groups and the first one is dual-stack' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4, manual_network_v6], [dynamic_net]])
    end

    it 'creates one NIC per group, dual-stacks the first, and only attaches LB/AGW to the primary NIC' do
      nic_params_list = capture_nic_params

      expect(nic_params_list.map { |p| p[:name] }).to eq(["#{vm_name}-0", "#{vm_name}-1"])
      expect(nic_params_list[0][:ip_configurations].length).to eq(2)
      expect(nic_params_list[1][:ip_configurations].length).to eq(1)

      expect(nic_params_list[0][:load_balancers]).to eq([load_balancer])
      expect(nic_params_list[0][:application_gateways]).to eq([application_gateway])
      expect(nic_params_list[1][:load_balancers]).to be_nil
      expect(nic_params_list[1][:application_gateways]).to be_nil
    end
  end

  context 'single-stack IPv4 (regression): one network per nic_group' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4], [dynamic_net]])
    end

    it 'creates one NIC per network, each with a single IPv4 ipConfiguration' do
      nic_params_list = capture_nic_params

      expect(nic_params_list.length).to eq(2)
      expect(nic_params_list[0][:ip_configurations]).to match([
        a_hash_including(ip_version: 'IPv4', private_ip: '10.0.0.5')
      ])
      expect(nic_params_list[1][:ip_configurations].length).to eq(1)
      expect(nic_params_list[1][:ip_configurations][0][:ip_version]).to eq('IPv4')
    end
  end

  context 'when a vip network targets a secondary nic_group' do
    let(:public_ip_address) { '203.0.113.10' }
    let(:public_ip) { { id: 'fake-public-ip-id', ip_address: public_ip_address } }
    let(:vip_network_for_second_nic) do
      instance_double(
        Bosh::AzureCloud::VipNetwork,
        resource_group_name: MOCK_RESOURCE_GROUP_NAME,
        public_ip: public_ip_address,
        spec: { 'type' => 'vip', 'nic_group' => '2' }
      )
    end

    before do
      allow(network_configurator).to receive(:vip_network).and_return(vip_network_for_second_nic)
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4, manual_network_v6], [dynamic_net]])
      allow(azure_client).to receive(:list_public_ips).and_return([public_ip])
    end

    it 'attaches the public IP to the NIC for that group' do
      nic_params_list = capture_nic_params

      expect(nic_params_list[0][:public_ip]).to be_nil
      expect(nic_params_list[1][:public_ip]).to eq(public_ip)
    end

    context 'when the referenced nic_group does not exist' do
      before do
        allow(vip_network_for_second_nic).to receive(:spec)
          .and_return({ 'type' => 'vip', 'nic_group' => 'missing' })
      end

      it 'fails instead of attaching the public IP to the primary NIC' do
        expect { capture_nic_params }.to raise_error(
          Bosh::Clouds::CloudError,
          "Cannot find nic_group 'missing' referenced by the vip network"
        )
      end
    end
  end

  context 'when a legacy vip network has no explicit nic_group' do
    let(:public_ip_address) { '203.0.113.10' }
    let(:public_ip) { { id: 'fake-public-ip-id', ip_address: public_ip_address } }
    let(:legacy_vip_network) do
      Bosh::AzureCloud::VipNetwork.new(
        azure_config_managed,
        'public',
        { 'type' => 'vip', 'ip' => public_ip_address }
      )
    end

    before do
      allow(network_configurator).to receive(:vip_network).and_return(legacy_vip_network)
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4, manual_network_v6], [dynamic_net]])
      allow(azure_client).to receive(:list_public_ips).and_return([public_ip])
    end

    it 'keeps attaching the public IP to the primary NIC' do
      nic_params_list = capture_nic_params

      expect(nic_params_list[0][:public_ip]).to eq(public_ip)
      expect(nic_params_list[1][:public_ip]).to be_nil
    end
  end

  describe '#_get_load_balancers' do
    let(:backend_pool_name_v6) { 'pool-v6' }
    let(:pool_v4) { { name: 'pool-v4', id: 'pool-v4-id' } }
    let(:pool_v6) { { name: 'pool-v6', id: 'pool-v6-id' } }
    let(:load_balancer) do
      {
        name: 'fake-lb-name',
        backend_address_pools: [pool_v4, pool_v6]
      }
    end
    let(:vm_properties) do
      {
        'instance_type' => 'Standard_D1',
        'load_balancer' => {
          'name' => 'fake-lb-name',
          'backend_pool_name' => 'pool-v4',
          'backend_pool_name_v6' => backend_pool_name_v6
        }
      }
    end

    it 'selects the configured backend pool for each IP family' do
      result = vm_manager_ds.send(:_get_load_balancers, vm_props)

      expect(result).to match([
        a_hash_including(
          backend_address_pools: [pool_v4],
          backend_address_pools_v6: [pool_v6]
        )
      ])
    end

    context 'when the configured IPv6 backend pool does not exist' do
      let(:backend_pool_name_v6) { 'missing-v6-pool' }

      it 'raises a cloud error naming the missing pool' do
        expect do
          vm_manager_ds.send(:_get_load_balancers, vm_props)
        end.to raise_error(
          Bosh::Clouds::CloudError,
          /does not have a backend_pool named 'missing-v6-pool'/
        )
      end
    end
  end

  describe '#_build_nic_groups_to_iface' do
    let(:group_one_v4) { instance_double(Bosh::AzureCloud::ManualNetwork, spec: { 'nic_group' => '1' }) }
    let(:group_one_v6) { instance_double(Bosh::AzureCloud::ManualNetwork, spec: { 'nic_group' => '1' }) }
    let(:ungrouped) { instance_double(Bosh::AzureCloud::DynamicNetwork, spec: { 'type' => 'dynamic' }) }
    let(:group_two) { instance_double(Bosh::AzureCloud::ManualNetwork, spec: { 'nic_group' => '2' }) }

    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[group_one_v4, group_one_v6], [ungrouped], [group_two]])
    end

    it 'maps explicit groups to their NIC attachment order and omits implicit groups' do
      mapping = vm_manager_ds.send(:_build_nic_groups_to_iface, network_configurator)

      expect(mapping).to eq('1' => 'eth0', '2' => 'eth2')
    end
  end
end
