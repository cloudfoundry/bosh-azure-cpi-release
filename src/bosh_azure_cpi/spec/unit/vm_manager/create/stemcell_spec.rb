# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - resource_group_name
  #   - default_security_group
  describe '#create' do
    context 'when VM is created' do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Stemcell
      context '#stemcell' do
        context 'when a heavy stemcell is used' do
          it 'should succeed' do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            expect(client2).to receive(:create_network_interface).exactly(2).times
            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:image_uri]).to eq(stemcell_uri)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end

        context 'when a light stemcell is used' do
          let(:platform_image) do
            {
              'publisher' => 'fake-publisher',
              'offer'     => 'fake-offer',
              'sku'       => 'fake-sku',
              'version'   => 'fake-version'
            }
          end

          before do
            allow(stemcell_info).to receive(:is_light_stemcell?)
              .and_return(true)
            allow(stemcell_info).to receive(:image_reference)
              .and_return(platform_image)
          end

          it 'should succeed' do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)

            expect(client2).to receive(:create_network_interface).twice
            vm_params = vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end
      end
    end
  end
end
