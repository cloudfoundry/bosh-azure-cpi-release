# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    context 'when VM is created' do
      before do
        allow(client2).to receive(:create_virtual_machine)
        allow(vm_manager).to receive(:get_stemcell_info).and_return(stemcell_info)
        allow(vm_manager2).to receive(:get_stemcell_info).and_return(stemcell_info)
      end

      # Availability Set
      context '#availability_set' do
        context 'when availability set is not created' do
          let(:env) { nil }
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:vm_properties) do
            {
              'instance_type' => 'Standard_D1',
              'availability_set' => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count' => 3
            }
          end

          before do
            allow(client2).to receive(:get_availability_set_by_name)
              .with(resource_group_name, availability_set_name)
              .and_return(nil)
            allow(client2).to receive(:create_availability_set)
              .and_raise('availability set is not created')
          end

          it 'should delete nics and then raise an error' do
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
              .and_call_original

            expect(client2).to receive(:delete_network_interface).exactly(2).times

            expect do
              vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            end.to raise_error /availability set is not created/
          end
        end

        context 'with env is nil and availability_set is specified in vm_types or vm_extensions' do
          let(:env) { nil }
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:vm_properties) do
            {
              'instance_type'                => 'Standard_D1',
              'availability_set'             => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count'  => 3
            }
          end
          let(:avset_params) do
            {
              name: vm_properties['availability_set'],
              location: location,
              tags: { 'user-agent' => 'bosh' },
              platform_update_domain_count: vm_properties['platform_update_domain_count'],
              platform_fault_domain_count: vm_properties['platform_fault_domain_count'],
              managed: false
            }
          end
          let(:availability_set) do
            {
              name: availability_set_name
            }
          end

          before do
            allow(client2).to receive(:get_availability_set_by_name)
              .with(resource_group_name, vm_properties['availability_set'])
              .and_return(nil, availability_set)
          end

          it 'should create availability set with the name specified in vm_types or vm_extensions' do
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
              .and_call_original
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
              .and_call_original

            expect(client2).to receive(:create_availability_set)
              .with(resource_group_name, avset_params)
            expect(client2).to receive(:create_network_interface).twice

            vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
            expect(vm_params[:name]).to eq(vm_name)
          end
        end

        context 'with bosh.group specified in env' do
          context 'when availability_set is specified in vm_types or vm_extensions' do
            let(:env) do
              {
                'bosh' => {
                  'group' => "bosh-group-#{SecureRandom.uuid}"
                }
              }
            end
            let(:availability_set_name) { SecureRandom.uuid.to_s }
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              }
            end
            let(:avset_params) do
              {
                name: vm_properties['availability_set'],
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: vm_properties['platform_update_domain_count'],
                platform_fault_domain_count: vm_properties['platform_fault_domain_count'],
                managed: false
              }
            end
            let(:availability_set) do
              {
                name: availability_set_name
              }
            end

            before do
              allow(client2).to receive(:get_availability_set_by_name)
                .with(resource_group_name, vm_properties['availability_set'])
                .and_return(nil, availability_set)
            end

            it 'should create availability set with the name specified in vm_types or vm_extensions' do
              expect(vm_manager).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                .and_call_original
              expect(vm_manager).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                .and_call_original

              expect(client2).to receive(:create_availability_set)
                .with(resource_group_name, avset_params)

              vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context 'when availability_set is not specified in vm_types or vm_extensions' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1'
              }
            end
            let(:avset_params) do
              {
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 5,
                platform_fault_domain_count: 3,
                managed: false
              }
            end

            context 'when the length of availability_set name equals to 80' do
              let(:env) do
                {
                  'bosh' => { 'group' => 'group' * 16 }
                }
              end
              let(:availability_set) do
                {
                  name: env['bosh']['group']
                }
              end

              before do
                avset_params[:name] = env['bosh']['group']
                allow(client2).to receive(:get_availability_set_by_name)
                  .with(resource_group_name, env['bosh']['group'])
                  .and_return(nil, availability_set)
              end

              it 'should create availability set and use value of env.bosh.group as its name' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{env['bosh']['group']}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{env['bosh']['group']}", File::LOCK_EX)
                  .and_call_original

                expect(client2).to receive(:create_availability_set)
                  .with(resource_group_name, avset_params)

                vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context 'when the length of availability_set name is greater than 80' do
              let(:env) do
                {
                  'bosh' => { 'group' => 'a' * 80 + 'group' * 8 }
                }
              end

              # 21d9858fb04d8ba39cdacdc926c5415e is MD5 of the availability_set name ('a' * 80 + 'group' * 8)
              let(:availability_set_name) { "az-21d9858fb04d8ba39cdacdc926c5415e-#{'group' * 8}" }
              let(:availability_set) do
                {
                  name: availability_set_name
                }
              end

              before do
                avset_params[:name] = availability_set_name
                allow(client2).to receive(:get_availability_set_by_name)
                  .and_return(nil, availability_set)
              end

              it 'should create availability set with a truncated value of env.bosh.group as its name' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{avset_params[:name]}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{avset_params[:name]}", File::LOCK_EX)
                  .and_call_original

                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)

                vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end
          end
        end

        context "when the availability set doesn't exist" do
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:availability_set) do
            {
              name: availability_set_name
            }
          end

          before do
            allow(client2).to receive(:get_availability_set_by_name)
              .with(resource_group_name, availability_set_name)
              .and_return(nil, availability_set)
          end

          context 'when platform_update_domain_count and platform_fault_domain_count are set' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 4,
                'platform_fault_domain_count' => 1
              }
            end
            let(:avset_params) do
              {
                name: vm_properties['availability_set'],
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 4,
                platform_fault_domain_count: 1
              }
            end

            context 'when the availability set is unmanaged' do
              before do
                avset_params[:managed] = false
              end

              it 'should create the unmanaged availability set' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                  .and_call_original

                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                expect(client2).to receive(:create_network_interface).twice

                vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context 'when the availability set is managed' do
              before do
                avset_params[:managed] = true
              end

              it 'should create the managed availability set' do
                expect(vm_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                  .and_call_original

                expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                expect(client2).to receive(:create_network_interface).twice

                vm_params = vm_manager2.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end
          end

          context 'when platform_update_domain_count and platform_fault_domain_count are not set' do
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name
              }
            end
            let(:avset_params) do
              {
                name: vm_properties['availability_set'],
                location: location,
                tags: { 'user-agent' => 'bosh' }
              }
            end

            context 'when the environment is not AzureStack' do
              context 'when the availability set is unmanaged' do
                before do
                  avset_params[:platform_update_domain_count] = 5
                  avset_params[:platform_fault_domain_count]  = 3
                  avset_params[:managed]                      = false
                end

                it 'should create the unmanaged availability set' do
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original

                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end

              context 'when the availability set is managed' do
                before do
                  avset_params[:platform_update_domain_count] = 5
                  avset_params[:platform_fault_domain_count]  = 2
                  avset_params[:managed]                      = true
                end

                it 'should create the managed availability set' do
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original

                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager2.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end
            end

            context 'when the environment is AzureStack' do
              # VM manager for AzureStack
              let(:azure_config_azure_stack) do
                mock_azure_config_merge(
                  'environment' => 'AzureStack'
                )
              end
              let(:vm_manager_azure_stack) { Bosh::AzureCloud::VMManager.new(azure_config_azure_stack, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }

              before do
                allow(vm_manager_azure_stack).to receive(:get_stemcell_info).and_return(stemcell_info)
              end

              # Only unmanaged availability set is supported on AzureStack
              context 'when the availability set is unmanaged' do
                before do
                  avset_params[:platform_update_domain_count] = 1
                  avset_params[:platform_fault_domain_count]  = 1
                  avset_params[:managed]                      = false
                end

                it 'should create the unmanaged availability set' do
                  expect(vm_manager_azure_stack).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager_azure_stack).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original

                  expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
                  expect(client2).to receive(:create_network_interface).twice

                  vm_params = vm_manager_azure_stack.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end
            end
          end
        end

        context 'when the availability set exists' do
          context 'when the availability set is in a different location' do
            let(:env) { nil }
            let(:availability_set_name) { SecureRandom.uuid.to_s }
            let(:availability_set) do
              {
                name: availability_set_name,
                virtual_machines: [
                  'fake-vm-id-1',
                  'fake-vm-id-2'
                ],
                location: "different-from-#{location}"
              }
            end
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              }
            end

            before do
              allow(client2).to receive(:get_availability_set_by_name)
                .with(resource_group_name, vm_properties['availability_set'])
                .and_return(availability_set)
            end

            it 'should not create the availability set and then raise an error' do
              expect(client2).not_to receive(:create_availability_set)
              expect(client2).to receive(:delete_network_interface).exactly(2).times

              expect do
                vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              end.to raise_error /create_availability_set - the availability set '#{availability_set_name}' already exists, but in a different location/
            end
          end

          context 'when the managed property is aligned with @use_managed_disks' do
            let(:env) { nil }
            let(:availability_set_name) { SecureRandom.uuid.to_s }
            let(:availability_set) do
              {
                name: availability_set_name,
                virtual_machines: [
                  'fake-vm-id-1',
                  'fake-vm-id-2'
                ],
                location: location.to_s
              }
            end
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              }
            end

            before do
              allow(client2).to receive(:get_availability_set_by_name)
                .with(resource_group_name, vm_properties['availability_set'])
                .and_return(availability_set)
            end

            it 'should not create availability set' do
              expect(client2).not_to receive(:create_availability_set)

              vm_params = vm_manager.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context 'when the managed property is not aligned with @use_managed_disks' do
            let(:availability_set_name) { SecureRandom.uuid.to_s }
            let(:vm_properties) do
              {
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name
              }
            end

            let(:existing_avset) do
              {
                name: vm_properties['availability_set'],
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 5,
                platform_fault_domain_count: 3,
                managed: false
              }
            end
            let(:avset_params) do
              {
                name: existing_avset[:name],
                location: existing_avset[:location],
                tags: existing_avset[:tags],
                platform_update_domain_count: existing_avset[:platform_update_domain_count],
                platform_fault_domain_count: existing_avset[:platform_fault_domain_count],
                managed: true
              }
            end

            before do
              allow(client2).to receive(:get_availability_set_by_name)
                .with(resource_group_name, vm_properties['availability_set'])
                .and_return(existing_avset)
            end

            it 'should update the managed property of the availability set' do
              expect(vm_manager2).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                .and_call_original
              expect(vm_manager2).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                .and_call_original

              expect(client2).to receive(:create_availability_set).with(resource_group_name, avset_params)
              expect(client2).to receive(:create_network_interface).twice

              vm_params = vm_manager2.create(instance_id, location, stemcell_id, vm_properties, network_configurator, env)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end
        end
      end
    end
  end
end
