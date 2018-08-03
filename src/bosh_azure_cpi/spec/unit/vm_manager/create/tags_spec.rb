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
      # Tags
      context '#tags' do
        context 'when tags is specified in vm_types or vm_extensions' do
          let(:custom_tags) do
            {
              'tag-name-1' => 'tag-value-1',
              'tag-name-2' => 'tag-value-2'
            }
          end
          let(:vm_properties) do
            {
              'instance_type' => 'Standard_D1',
              'tags' => custom_tags
            }
          end
          it 'should set the tags for the VM' do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).to receive(:create_virtual_machine)
              .with(resource_group_name, hash_including(tags: custom_tags.merge(Bosh::AzureCloud::Helpers::AZURE_TAGS)), any_args)
            expect do
              vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            end.not_to raise_error
          end
        end
      end
    end
  end
end
