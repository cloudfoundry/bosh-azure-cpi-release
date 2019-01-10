# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    let(:agent_util) { instance_double(Bosh::AzureCloud::BoshAgentUtil) }
    let(:network_spec) { {} }
    let(:config) { instance_double(Bosh::AzureCloud::Config) }

    before do
      allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
    end

    context 'when VM is created' do
      before do
        allow(azure_client).to receive(:create_virtual_machine)
      end

      context '#managed_identity' do
        context 'when managed identity is nil in vm_props' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1'
            )
          end

          it 'should not enable managed identity' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
            expect(vm_params.keys).not_to include('identity')
          end
        end

        context 'when managed identity is not nil in vm_props' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1',
              'managed_identity' => {
                'type' => 'UserAssigned',
                'user_assigned_identity_name' => 'fake-identity-name'
              }
            )
          end

          it 'should not enable managed identity' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
            expect(vm_params[:identity][:type]).to eq('UserAssigned')
            expect(vm_params[:identity][:identity_name]).to eq('fake-identity-name')
          end
        end
      end
    end
  end
end
