# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  let(:vnet_id) do
    '/subscriptions/fake-subscription/resourceGroups/fake-resource-group/providers/Microsoft.Network/virtualNetworks/fake-vnet'
  end

  describe '#_build_backend_address' do
    it 'builds an Azure backend address with the supplied VM name' do
      backend_address = vm_manager.send(:_build_backend_address, {}, 'fake-vm', '10.0.0.5', vnet_id)

      expect(backend_address).to eq(
        name: 'fake-vm',
        properties: {
          ipAddress: '10.0.0.5',
          virtualNetwork: { id: vnet_id }
        }
      )
    end

    it 'generates a name when the VM name is omitted' do
      allow(SecureRandom).to receive(:uuid).and_return('generated-uuid')

      backend_address = vm_manager.send(:_build_backend_address, {}, '', 'fd00::5', vnet_id)

      expect(backend_address[:name]).to eq('generated-uuid')
    end
  end

  describe '#_calculate_backend_addresses_for_load_balancer' do
    let(:load_balancer) do
      {
        backend_address_pools: [
          { name: 'pool-v4', backend_address_pools_type: Bosh::AzureCloud::Helpers::LOAD_BALANCER_BACKEND_POOL_TYPE_IP },
          { name: 'pool-nic', backend_address_pools_type: Bosh::AzureCloud::Helpers::LOAD_BALANCER_BACKEND_POOL_TYPE_NIC }
        ],
        backend_address_pools_v6: [
          { name: 'pool-v6', backend_address_pools_type: Bosh::AzureCloud::Helpers::LOAD_BALANCER_BACKEND_POOL_TYPE_IP }
        ]
      }
    end
    let(:vm_network_interfaces) do
      [
        {
          primary: true,
          ip_configurations: [
            {
              private_ip: '10.0.0.5',
              private_ip_address_version: 'IPv4',
              subnet: { id: "#{vnet_id}/subnets/fake-subnet" }
            },
            {
              private_ip: 'fd00::5',
              private_ip_address_version: 'IPv6',
              subnet: { id: "#{vnet_id}/subnets/fake-subnet" }
            }
          ]
        },
        {
          primary: false,
          ip_configurations: [
            {
              private_ip: '',
              private_ip_address_version: 'IPv4',
              subnet: { id: "#{vnet_id}/subnets/fake-subnet" }
            }
          ]
        }
      ]
    end

    it 'builds addresses for each IP-based pool and skips NIC-based pools and empty IPs' do
      allow(SecureRandom).to receive(:uuid).and_return('ipv4-address', 'ipv6-address')

      result = vm_manager.send(
        :_calculate_backend_addresses_for_load_balancer,
        load_balancer,
        vm_network_interfaces
      )

      expect(result).to eq([
        {
          name: 'pool-v4',
          loadBalancerBackendAddresses: [
            {
              name: 'ipv4-address',
              properties: { ipAddress: '10.0.0.5', virtualNetwork: { id: vnet_id } }
            }
          ]
        },
        {
          name: 'pool-v6',
          loadBalancerBackendAddresses: [
            {
              name: 'ipv6-address',
              properties: { ipAddress: 'fd00::5', virtualNetwork: { id: vnet_id } }
            }
          ]
        }
      ])
    end

    it 'omits pools that have no matching VM addresses' do
      expect(
        vm_manager.send(
          :_calculate_backend_addresses_for_load_balancer,
          load_balancer,
          [{ primary: true, ip_configurations: [] }]
        )
      ).to be_empty
    end

    it 'returns no backend addresses when the VM has no primary NIC' do
      expect(
        vm_manager.send(
          :_calculate_backend_addresses_for_load_balancer,
          load_balancer,
          [{ primary: false, ip_configurations: [] }]
        )
      ).to eq([])
    end

    it 'calculates IPv4 addresses when the IPv6 pools are nil' do
      load_balancer[:backend_address_pools_v6] = nil
      allow(SecureRandom).to receive(:uuid).and_return('ipv4-address')

      result = vm_manager.send(
        :_calculate_backend_addresses_for_load_balancer,
        load_balancer,
        vm_network_interfaces
      )

      expect(result).to eq([
        {
          name: 'pool-v4',
          loadBalancerBackendAddresses: [
            {
              name: 'ipv4-address',
              properties: { ipAddress: '10.0.0.5', virtualNetwork: { id: vnet_id } }
            }
          ]
        }
      ])
    end
  end

  describe '#_add_vm_to_load_balancer_backend_pool' do
    let(:resource_group_name) { 'fake-resource-group' }
    let(:load_balancers) { [{ name: 'fake-lb', resource_group_name: resource_group_name }] }
    let(:virtual_machine_result) { { name: 'fake-vm-name', network_interfaces: [{ ip_configurations: [] }] } }

    before do
      allow(vm_manager).to receive(:flock).and_yield
    end

    it 'does nothing when the VM result or load balancers are absent' do
      expect(azure_client).not_to receive(:get_load_balancer_by_name)

      vm_manager.send(:_add_vm_to_load_balancer_backend_pool, nil, virtual_machine_result)
      vm_manager.send(:_add_vm_to_load_balancer_backend_pool, [], virtual_machine_result)
      vm_manager.send(:_add_vm_to_load_balancer_backend_pool, load_balancers, nil)
    end

    it 'merges existing addresses and updates the matching pool under a lock' do
      new_address = {
        name: 'new-address',
        properties: { ipAddress: '10.0.0.5', virtualNetwork: { id: vnet_id } }
      }
      existing_address = {
        'name' => 'existing-vm',
        'properties' => {
          'ipAddress' => '10.0.0.4',
          'virtualNetwork' => { 'id' => vnet_id }
        }
      }
      calculated_pools = [
        { name: 'POOL-V4', loadBalancerBackendAddresses: [new_address] }
      ]
      current_load_balancer = {
        backend_address_pools: [
          { name: 'pool-v4', load_balancer_backend_addresses: [existing_address] },
          { name: 'unmatched-pool', load_balancer_backend_addresses: [] }
        ]
      }
      rebuilt_existing_address = {
        name: 'existing-vm',
        properties: { 'ipAddress' => '10.0.0.4', 'virtualNetwork' => { 'id' => vnet_id } }
      }

      allow(vm_manager).to receive(:_calculate_backend_addresses_for_load_balancer)
        .with(load_balancers.first, virtual_machine_result[:network_interfaces])
        .and_return(calculated_pools)
      expect(vm_manager).to receive(:flock)
        .with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX)
        .and_yield
      expect(azure_client).to receive(:get_load_balancer_by_name)
        .with(resource_group_name, 'fake-lb')
        .and_return(current_load_balancer)
      expect(azure_client).to receive(:update_load_balancer_backend_pool)
        .with(resource_group_name, 'fake-lb', 'pool-v4', [new_address, rebuilt_existing_address])

      vm_manager.send(
        :_add_vm_to_load_balancer_backend_pool,
        load_balancers,
        virtual_machine_result
      )
    end
  end

  describe '#_remove_vm_from_load_balancer_backend_pool' do
    let(:resource_group_name) { 'fake-resource-group' }
    let(:virtual_machine_result) do
      {
        name: 'fake-vm-name',
        network_interfaces: [
          {
            tags: network_interface_tags,
            ip_configurations: [first_ip_configuration, second_ip_configuration]
          }
        ]
      }
    end
    let(:network_interface_tags) do
      { Bosh::AzureCloud::Helpers::LOAD_BALANCER_USED_BY_TAG => true }
    end
    let(:first_ip_configuration) do
      {
        private_ip: '10.0.0.5',
        subnet: { id: "#{vnet_id}/subnets/fake-subnet" }
      }
    end
    let(:second_ip_configuration) do
      {
        private_ip: '10.0.0.6',
        subnet: { id: "#{vnet_id}/subnets/fake-subnet" }
      }
    end
    let(:backend_pool_references) do
      [
        {
          id: '/subscriptions/fake-subscription/resourceGroups/fake-resource-group/providers/Microsoft.Network/loadBalancers/fake-lb/backendAddressPools/pool-v4'
        }
      ]
    end
    let(:removed_address) do
      {
        'name' => 'removed-vm',
        'properties' => {
          'ipAddress' => '10.0.0.5',
          'virtualNetwork' => { 'id' => vnet_id }
        }
      }
    end
    let(:retained_address) do
      {
        'name' => 'retained-vm',
        'properties' => {
          'ipAddress' => '10.0.0.6',
          'virtualNetwork' => { 'id' => vnet_id }
        }
      }
    end
    let(:load_balancers) do
      [
        {
          id: "/subscriptions/fake-subscription/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/fake-lb",
          name: 'fake-lb',
          backend_address_pools: [
            {
              name: 'pool-v4',
              load_balancer_backend_addresses: [removed_address, retained_address]
            }
          ]
        }
      ]
    end

    before do
      allow(azure_client).to receive(:list_all_load_balancers).and_return(load_balancers)
    end

    context 'when the VM is not marked as used by a load balancer' do
      let(:network_interface_tags) { {} }

      it 'does not inspect or update load balancers' do
        expect(vm_manager).not_to receive(:flock)
        expect(azure_client).not_to receive(:list_all_load_balancers)
        expect(azure_client).not_to receive(:update_load_balancer_backend_pool)

        vm_manager.send(:_remove_vm_from_load_balancer_backend_pool, virtual_machine_result)
      end
    end

    context 'when both IP configurations have the backend pool property' do
      let(:first_ip_configuration) do
        super().merge(load_balancers: backend_pool_references)
      end
      let(:second_ip_configuration) do
        super().merge(load_balancers: backend_pool_references)
      end

      it 'does not update IP-based backend addresses' do
        expect(vm_manager).not_to receive(:flock)
        expect(azure_client).not_to receive(:update_load_balancer_backend_pool)

        vm_manager.send(
          :_remove_vm_from_load_balancer_backend_pool,
          virtual_machine_result
        )
      end
    end

    context 'when only one IP configuration has the backend pool property' do
      let(:second_ip_configuration) do
        super().merge(load_balancers: backend_pool_references)
      end

      it 'removes the unmarked address and preserves the marked address' do
        expect(vm_manager).to receive(:flock)
          .with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX)
          .and_yield
        expect(azure_client).to receive(:update_load_balancer_backend_pool)
          .with(
            resource_group_name,
            'fake-lb',
            'pool-v4',
            [
              {
                name: 'retained-vm',
                properties: { 'ipAddress' => '10.0.0.6', 'virtualNetwork' => { 'id' => vnet_id } }
              }
            ]
          )

        vm_manager.send(
          :_remove_vm_from_load_balancer_backend_pool,
          virtual_machine_result
        )
      end
    end

    context 'when neither IP configuration has the backend pool property' do
      it 'removes both addresses from the backend pool' do
        expect(vm_manager).to receive(:flock)
          .with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX)
          .and_yield
        expect(azure_client).to receive(:update_load_balancer_backend_pool)
          .with(resource_group_name, 'fake-lb', 'pool-v4', [])

        vm_manager.send(
          :_remove_vm_from_load_balancer_backend_pool,
          virtual_machine_result
        )
      end
    end

    context 'when the load balancer response has no backend address pools' do
      let(:load_balancers) do
        [
          {
            id: "/subscriptions/fake-subscription/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/fake-lb/backendAddressPools/pool-v4",
            name: 'pool-v4',
            provisioning_state: 'Succeeded',
            backend_ip_configurations: [
              {
                id: '/subscriptions/fake-subscription/resourceGroups/fake-resource-group/providers/Microsoft.Network/networkInterfaces/fake-nic/ipConfigurations/fake-ip-config'
              }
            ]
          }
        ]
      end

      it 'does not update a backend pool' do
        expect(vm_manager).to receive(:flock)
          .with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX)
          .and_yield
        expect(azure_client).not_to receive(:update_load_balancer_backend_pool)

        expect do
          vm_manager.send(
            :_remove_vm_from_load_balancer_backend_pool,
            virtual_machine_result
          )
        end.not_to raise_error
      end
    end

    context 'when a backend address pool has no backend addresses' do
      let(:load_balancers) do
        [
          {
            id: "/subscriptions/fake-subscription/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/fake-lb",
            name: 'fake-lb',
            backend_address_pools: [
              {
                name: 'pool-v4',
                backend_ip_configurations: [
                  {
                    id: '/subscriptions/fake-subscription/resourceGroups/fake-resource-group/providers/Microsoft.Network/networkInterfaces/fake-nic/ipConfigurations/fake-ip-config'
                  }
                ]
              }
            ]
          }
        ]
      end

      it 'does not update a backend pool or raise an error' do
        expect(vm_manager).to receive(:flock)
          .with("#{Bosh::AzureCloud::Helpers::CPI_LOCK_LOAD_BALANCER}-all", File::LOCK_EX)
          .and_yield
        expect(azure_client).not_to receive(:update_load_balancer_backend_pool)

        expect do
          vm_manager.send(
            :_remove_vm_from_load_balancer_backend_pool,
            virtual_machine_result
          )
        end.not_to raise_error
      end
    end

    it 'does nothing when load balancers are not found' do
      allow(azure_client).to receive(:list_all_load_balancers).and_return(nil)
      expect(azure_client).not_to receive(:update_load_balancer_backend_pool)

      vm_manager.send(:_remove_vm_from_load_balancer_backend_pool, virtual_machine_result)
    end
  end
end
