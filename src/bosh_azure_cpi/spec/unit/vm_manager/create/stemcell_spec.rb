# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - resource_group_name
  #   - default_security_group
  describe '#create' do
    let(:agent_util) { instance_double(Bosh::AzureCloud::BoshAgentUtil) }
    let(:network_spec) { {} }
    let(:config) { instance_double(Bosh::AzureCloud::Config) }

    context 'when VM is created' do
      before do
        allow(azure_client).to receive(:create_virtual_machine)
        allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
      end

      # Stemcell
      context '#stemcell' do
        context 'when a heavy stemcell is used' do
          it 'should succeed' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)

            expect(azure_client).to receive(:create_network_interface).exactly(2).times
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:image_uri]).to eq(stemcell_uri)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end

        context 'when a light stemcell is used' do
          let(:platform_image) do
            {
              'publisher' => 'fake-publisher',
              'offer' => 'fake-offer',
              'sku' => 'fake-sku',
              'version' => 'fake-version'
            }
          end

          before do
            allow(stemcell_info).to receive(:is_light_stemcell?)
              .and_return(true)
            allow(stemcell_info).to receive(:image_reference)
              .and_return(platform_image)
          end

          it 'should succeed' do
            expect(azure_client).not_to receive(:delete_virtual_machine)
            expect(azure_client).not_to receive(:delete_network_interface)

            expect(azure_client).to receive(:create_network_interface).twice
            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
            expect(vm_params[:name]).to eq(vm_name)
            expect(vm_params[:os_type]).to eq(os_type)
          end
        end
      end
    end
  end

  describe '#get_stemcell_info' do
    context 'when managed disks are used' do
      let(:storage_account_name) { nil }

      context 'when light stemcell is used' do
        let(:stemcell_cid) { 'bosh-light-stemcell-xxx' }

        context 'when stemcell does not exist' do
          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).with(location, stemcell_cid).and_return(false)
          end

          it 'should raise an error' do
            expect do
              vm_manager2.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            end.to raise_error("Given stemcell '#{stemcell_cid}' does not exist")
          end
        end

        context 'when stemcell exists' do
          let(:stemcell_info) { double('stemcell-info') }

          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).with(location, stemcell_cid).and_return(true)
            allow(light_stemcell_manager).to receive(:get_stemcell_info).with(stemcell_cid).and_return(stemcell_info)
          end

          it 'should return the stemcell info' do
            expect(
              vm_manager2.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            ).to be(stemcell_info)
          end
        end
      end

      context 'when heavy stemcell is used' do
        let(:stemcell_cid) { 'bosh-stemcell-xxx' }

        context 'when it gets user image successfully' do
          let(:stemcell_info) { double('stemcell-info') }

          before do
            allow(stemcell_manager2).to receive(:get_user_image_info)
              .with(stemcell_cid, 'Standard_LRS', location, https_traffic)
              .and_return(stemcell_info)
          end

          it 'should return the stemcell info' do
            expect(
              vm_manager2.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            ).to be(stemcell_info)
          end
        end

        context 'when it fails to user image successfully' do
          let(:stemcell_info) { double('stemcell-info') }

          before do
            allow(stemcell_manager2).to receive(:get_user_image_info)
              .with(stemcell_cid, 'Standard_LRS', location, https_traffic)
              .and_raise('fake-error')
          end

          it 'should return the stemcell info' do
            expect do
              vm_manager2.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            end.to raise_error(/Failed to get the user image information for the stemcell '#{stemcell_cid}'/)
          end
        end
      end
    end

    context 'when unmanaged disks are used' do
      let(:storage_account) do
        {
          name: 'fake-storage-account-name'
        }
      end

      before do
        allow(vm_manager).to receive(:get_storage_account_from_vm_properties)
          .with(vm_props, location)
          .and_return(storage_account)
      end

      context 'when light stemcell is used' do
        let(:stemcell_cid) { 'bosh-light-stemcell-xxx' }
        let(:storage_account_name) { nil }

        context 'when stemcell does not exist' do
          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).with(location, stemcell_cid).and_return(false)
          end

          it 'should raise an error' do
            expect do
              vm_manager.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            end.to raise_error("Given stemcell '#{stemcell_cid}' does not exist")
          end
        end

        context 'when stemcell exists' do
          let(:stemcell_info) { double('stemcell-info') }

          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).with(location, stemcell_cid).and_return(true)
            allow(light_stemcell_manager).to receive(:get_stemcell_info).with(stemcell_cid).and_return(stemcell_info)
          end

          it 'should return the stemcell info' do
            expect(
              vm_manager.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            ).to be(stemcell_info)
          end
        end
      end

      context 'when heavy stemcell is used' do
        let(:stemcell_cid) { 'bosh-stemcell-xxx' }
        let(:storage_account_name) { 'fake-storage-account-name' }

        context 'when it fails to get stemcell' do
          before do
            allow(stemcell_manager).to receive(:has_stemcell?)
              .with('fake-storage-account-name', stemcell_cid)
              .and_return(false)
          end

          it 'should raise an error' do
            expect do
              vm_manager.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            end.to raise_error("Given stemcell '#{stemcell_cid}' does not exist")
          end
        end

        context 'when it gets the stemcell successfully' do
          let(:stemcell_info) { double('stemcell-info') }

          before do
            allow(stemcell_manager).to receive(:has_stemcell?)
              .with('fake-storage-account-name', stemcell_cid)
              .and_return(true)
            allow(stemcell_manager).to receive(:get_stemcell_info)
              .with('fake-storage-account-name', stemcell_cid)
              .and_return(stemcell_info)
          end

          it 'should return stemcell info' do
            expect(
              vm_manager.send(:_get_stemcell_info, stemcell_cid, vm_props, location, storage_account_name)
            ).to be(stemcell_info)
          end
        end
      end
    end
  end
end
