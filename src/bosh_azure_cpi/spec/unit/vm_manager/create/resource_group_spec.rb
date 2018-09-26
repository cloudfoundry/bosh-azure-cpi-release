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
      allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
    end

    context 'when VM is created' do
      before do
        allow(azure_client).to receive(:create_virtual_machine)
      end

      # Resource group
      context 'when the resource group does not exist' do
        before do
          allow(azure_client).to receive(:get_resource_group)
            .with(MOCK_RESOURCE_GROUP_NAME)
            .and_return(nil)
          allow(azure_client).to receive(:create_network_interface)
        end

        it 'should create the resource group' do
          expect(azure_client).to receive(:create_resource_group)
            .with(MOCK_RESOURCE_GROUP_NAME, location)

          _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
          expect(vm_params[:name]).to eq(vm_name)
        end
      end
    end
  end
end
