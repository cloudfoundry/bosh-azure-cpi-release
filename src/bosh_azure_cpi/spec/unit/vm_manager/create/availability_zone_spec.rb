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
        allow(vm_manager).to receive(:get_stemcell_info).and_return(stemcell_info)
      end

      # Availability Zones
      context 'with availability zone specified' do
        let(:availability_zone) { '1' }

        before do
          vm_properties['availability_zone'] = availability_zone

          allow(network_configurator).to receive(:vip_network)
            .and_return(nil)
        end

        context 'and assign_dynamic_public_ip is true' do
          let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }

          before do
            vm_properties['assign_dynamic_public_ip'] = true
            allow(client2).to receive(:get_public_ip_by_name)
              .with(resource_group_name, vm_name).and_return(dynamic_public_ip)
          end

          it 'creates public IP and virtual machine in the specified zone' do
            expect(client2).to receive(:create_public_ip)
              .with(resource_group_name, hash_including(
                                           zone: availability_zone
                                         )).once
            expect(client2).to receive(:create_virtual_machine)
              .with(resource_group_name,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and assign_dynamic_public_ip is not set' do
          it 'creates virtual machine in the specified zone' do
            expect(client2).to receive(:create_virtual_machine)
              .with(resource_group_name,
                    hash_including(zone: availability_zone),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            expect(vm_params[:zone]).to eq(availability_zone)
          end
        end

        context 'and availability_zone is an integer' do
          before do
            vm_properties['availability_zone'] = 1
          end

          it 'convert availability_zone to string' do
            expect(client2).to receive(:create_virtual_machine)
              .with(resource_group_name,
                    hash_including(zone: '1'),
                    anything,
                    nil)             # Availability set must be nil when availability is specified

            vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            expect(vm_params[:zone]).to eq('1')
          end
        end
      end
    end
  end
end
