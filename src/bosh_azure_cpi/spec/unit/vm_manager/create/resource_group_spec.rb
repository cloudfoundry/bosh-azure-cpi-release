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

      # Resource group
      context 'when the resource group does not exist' do
        before do
          allow(client2).to receive(:get_resource_group)
            .with(resource_group_name)
            .and_return(nil)
          allow(client2).to receive(:create_network_interface)
        end

        it 'should create the resource group' do
          expect(client2).to receive(:create_resource_group)
            .with(resource_group_name, location)

          vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
          expect(vm_params[:name]).to eq(vm_name)
        end
      end
    end
  end
end
