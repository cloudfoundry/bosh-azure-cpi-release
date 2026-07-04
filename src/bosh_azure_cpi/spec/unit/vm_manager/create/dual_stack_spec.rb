# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager, 'dual-stack NIC creation' do
  include_context 'shared stuff for vm manager'

  subject(:vm_manager_ds) { vm_manager2 }

  let(:dual_stack_subnet) { double('dual-stack-subnet', id: 'fake-dual-stack-subnet-id') }

  let(:manual_network_v4) { build_manual_network(private_ip: '10.0.0.5', subnet_name: 'dual-stack-subnet') }
  let(:manual_network_v6) { build_manual_network(private_ip: 'fd00::5',  subnet_name: 'dual-stack-subnet') }
  let(:dynamic_net) do
    instance_double(Bosh::AzureCloud::DynamicNetwork).tap do |n|
      allow(n).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
      allow(n).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
      allow(n).to receive(:subnet_name).and_return('fake-subnet-name')
      allow(n).to receive(:security_group).and_return(empty_security_group)
      allow(n).to receive(:application_security_groups).and_return([])
      allow(n).to receive(:ip_forwarding).and_return(false)
      allow(n).to receive(:accelerated_networking).and_return(false)
    end
  end

  def build_manual_network(private_ip:, subnet_name:)
    instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
      allow(n).to receive(:is_a?) { |klass| klass == Bosh::AzureCloud::ManualNetwork }
      allow(n).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
      allow(n).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
      allow(n).to receive(:subnet_name).and_return(subnet_name)
      allow(n).to receive(:private_ip).and_return(private_ip)
      allow(n).to receive(:security_group).and_return(empty_security_group)
      allow(n).to receive(:application_security_groups).and_return([])
      allow(n).to receive(:ip_forwarding).and_return(false)
      allow(n).to receive(:accelerated_networking).and_return(false)
    end
  end

  def capture_nic_params
    captured = []
    allow(azure_client).to receive(:create_network_interface) { |_rg, params| captured << params }
    vm_manager_ds.send(:_create_network_interfaces,
                       MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                       vm_props, network_configurator)
    captured
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
        .and_return([[manual_network_v4, manual_network_v6]])
    end

    it 'creates one NIC with two ipConfigurations sharing the same subnet, one per IP family' do
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

      # Only the primary NIC gets LB / AGW attachments.
      expect(nic_params_list[0][:load_balancers]).not_to be_nil
      expect(nic_params_list[0][:application_gateways]).not_to be_nil
      expect(nic_params_list[1][:load_balancers]).to be_nil
      expect(nic_params_list[1][:application_gateways]).to be_nil
    end
  end

  context 'single-stack IPv4 (regression): one network per nic_group' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network], [dynamic_network]])
    end

    it 'creates one NIC per network, each with a single IPv4 ipConfiguration' do
      nic_params_list = capture_nic_params

      expect(nic_params_list.length).to eq(2)
      expect(nic_params_list[0][:ip_configurations]).to match([
        a_hash_including(ip_version: 'IPv4', private_ip: 'private-ip')
      ])
      expect(nic_params_list[1][:ip_configurations].length).to eq(1)
      expect(nic_params_list[1][:ip_configurations][0][:ip_version]).to eq('IPv4')
    end
  end
end
