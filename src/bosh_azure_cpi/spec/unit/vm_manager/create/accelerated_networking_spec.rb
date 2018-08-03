# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - resource_group_name
  #   - default_security_group
  describe '#create' do
    before do
      allow(vm_manager).to receive(:get_stemcell_info).and_return(stemcell_info)
    end

    context 'when VM is created' do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Accelerated Networking
      context '#accelerated_networking' do
        context 'when accelerated networking is disbaled in network specs' do
          before do
            allow(manual_network).to receive(:accelerated_networking).and_return(false)
            allow(dynamic_network).to receive(:accelerated_networking).and_return(false)
          end

          context 'when accelerated networking is not specified in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1'
              }
            end
            it 'should disable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is disabled in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => false
              }
            end
            it 'should disable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is enabled in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => true
              }
            end
            it 'should enable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end
        end

        context 'when accelerated networking is enabled in network specs' do
          before do
            allow(manual_network).to receive(:accelerated_networking).and_return(true)
            allow(dynamic_network).to receive(:accelerated_networking).and_return(true)
          end

          context 'when accelerated networking is not specified in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1'
              }
            end
            it 'should enable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is disabled in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => false
              }
            end
            it 'should disable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: false), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when accelerated networking is enabled in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'accelerated_networking' => true
              }
            end
            it 'should enable accelerated networking on the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(enable_accelerated_networking: true), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end
        end
      end
    end
  end
end
