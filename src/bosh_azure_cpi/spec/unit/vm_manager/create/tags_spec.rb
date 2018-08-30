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
      # Tags
      context '#tags' do
        context 'when tags is specified in vm_types or vm_extensions' do
          let(:custom_tags) do
            {
              'tag-name-1' => 'tag-value-1',
              'tag-name-2' => 'tag-value-2'
            }
          end
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1',
              'tags' => custom_tags
            )
          end
          it 'should set the tags for the VM' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(tags: custom_tags.merge(Bosh::AzureCloud::Helpers::AZURE_TAGS)), any_args)
            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            end.not_to raise_error
          end
        end
      end
    end
  end
end
