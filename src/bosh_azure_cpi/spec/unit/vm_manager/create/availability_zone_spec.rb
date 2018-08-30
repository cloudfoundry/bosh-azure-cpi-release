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
        allow(azure_client).to receive(:create_virtual_machine)
        allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
      end

      # Availability Zones
      context 'with availability zone specified' do
        let(:availability_zone) { '1' }

        before do
          vm_props.availability_zone = availability_zone

          allow(network_configurator).to receive(:vip_network)
            .and_return(nil)
        end

        context 'and assign_dynamic_public_ip is true' do
          let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }

          before do
            vm_props.assign_dynamic_public_ip = true
            allow(azure_client).to receive(:get_public_ip_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_name).and_return(dynamic_public_ip)
          end

          it 'creates public IP and virtual machine in the specified zone' do
            expect(azure_client).to receive(:create_public_ip)
              .with(MOCK_RESOURCE_GROUP_NAME, hash_including(
                                                zone: availability_zone
                                              )).once
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and assign_dynamic_public_ip is not set' do
          it 'creates virtual machine in the specified zone' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and availability_zone is an integer' do
          before do
            vm_props.availability_zone = 1
          end

          it 'convert availability_zone to string' do
            expect(azure_client).to receive(:create_virtual_machine)
              .with(MOCK_RESOURCE_GROUP_NAME,
                    hash_including(zone: '1'),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
            expect(vm_params[:zone]).to eq('1')
          end
        end
      end
    end
  end
end
