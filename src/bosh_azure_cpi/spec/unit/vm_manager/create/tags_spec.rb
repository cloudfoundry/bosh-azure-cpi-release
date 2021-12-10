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
      allow(azure_client).to receive(:delete_virtual_machine)
      allow(azure_client).to receive(:delete_network_interface)
    end

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

    context 'when VM is created' do
      context '#tags' do
        context 'when tags is specified in vm_types or vm_extensions' do
          it 'should set the tags for the VM' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(tags: custom_tags.merge(Bosh::AzureCloud::Helpers::AZURE_TAGS)), any_args)
            vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, anything, anything, anything)
          end
        end

        context 'when tags are specified in the incoming env' do
          let(:env) { { "bosh" => { "tags" => { 'tag-name-1' => 'value-from-env', 'tag-name-3' => 'other-env-value' } } } }

          it 'should set the tags for the VM' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(tags: env['bosh']['tags'].merge(Bosh::AzureCloud::Helpers::AZURE_TAGS)), any_args)
            vm_manager.create(bosh_vm_meta, location, props_factory.parse_vm_props({ 'instance_type' => 'Standard_D1' }), disk_cids, network_configurator, env, anything, anything, anything)
          end

          context 'when tags are also specified in vm_types' do
            it 'merges tags, preferring the cloud properties' do
              expected_tags = {
                'tag-name-1' => 'tag-value-1',
                'tag-name-2' => 'tag-value-2',
                'tag-name-3' => 'other-env-value'
              }
              expect(azure_client).to receive(:create_virtual_machine)
                .with(MOCK_RESOURCE_GROUP_NAME, hash_including(tags: expected_tags.merge(Bosh::AzureCloud::Helpers::AZURE_TAGS)), any_args)
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, anything, anything, anything)
            end
          end
        end
      end
    end
  end
end
