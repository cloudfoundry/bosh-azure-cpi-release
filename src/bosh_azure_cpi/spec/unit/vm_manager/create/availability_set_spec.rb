# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    let(:agent_util) { instance_double(Bosh::AzureCloud::BoshAgentUtil) }
    let(:network_spec) { {} }
    let(:config) { instance_double(Bosh::AzureCloud::Config) }

    context 'when VM is created' do
      before do
        allow(azure_client).to receive(:create_virtual_machine)
        allow(vm_manager).to receive(:_get_stemcell_info).and_return(stemcell_info)
        allow(vm_manager2).to receive(:_get_stemcell_info).and_return(stemcell_info)
      end

      # Availability Set
      context '#availability_set' do
        context 'when availability set is not created' do
          let(:env) { nil }
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1',
              'availability_set' => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count' => 3
            )
          end

          before do
            allow(azure_client).to receive(:get_availability_set_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, availability_set_name)
              .and_return(nil)
            allow(azure_client).to receive(:create_availability_set)
              .and_raise('availability set is not created')
          end

          it 'should delete nics and then raise an error' do
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
              .and_call_original

            expect(azure_client).to receive(:delete_network_interface).exactly(2).times

            expect do
              vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
            end.to raise_error /availability set is not created/
          end
        end

        context 'when instance_type is nil and instance_types exist' do
          let(:env) { nil }
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:platform_update_domain_count) { 5 }
          let(:platform_fault_domain_count) { 3 }
          let(:availability_set) do
            {
              name: availability_set_name,
              location: location
            }
          end
          before do
            allow(azure_client).to receive(:get_availability_set_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
              .and_return(availability_set)
            allow(azure_client).to receive(:create_availability_set)
          end

          let(:instance_types) { %w[Standard_DS2_v3 Standard_D2_v3] }
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => nil,
              'instance_types' => instance_types,
              'availability_set' => availability_set_name,
              'platform_update_domain_count' => platform_update_domain_count,
              'platform_fault_domain_count' => platform_fault_domain_count
            )
          end

          context 'when disk_cids are not provided' do
            let(:disk_cids) { nil }

            context 'when all instance types are available in the availaiblity set' do
              let(:available_vm_sizes) do
                [
                  {
                    name: 'Standard_DS2_v3',
                    number_of_cores: '2',
                    memory_in_mb: 4096
                  },
                  {
                    name: 'Standard_D2_v3',
                    number_of_cores: '2',
                    memory_in_mb: 4096
                  }
                ]
              end

              before do
                allow(azure_client).to receive(:list_available_virtual_machine_sizes_by_availability_set)
                  .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                  .and_return(available_vm_sizes)
              end

              it 'should select a VM size which is available in the availability set' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                  .and_call_original
                expect(azure_client).to receive(:create_network_interface).twice

                _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                expect(vm_params[:name]).to eq(vm_name)
                expect(vm_props.instance_type).to eq('Standard_DS2_v3')
              end
            end

            context 'when some instance types are available in the availaiblity set' do
              let(:available_vm_sizes) do
                [
                  {
                    name: 'Standard_D2_v3',
                    number_of_cores: '2',
                    memory_in_mb: 4096
                  }
                ]
              end

              before do
                allow(azure_client).to receive(:list_available_virtual_machine_sizes_by_availability_set)
                  .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                  .and_return(available_vm_sizes)
              end

              it 'should select a VM size which is available in the availability set' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                  .and_call_original
                expect(azure_client).to receive(:create_network_interface).twice

                _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                expect(vm_params[:name]).to eq(vm_name)
                expect(vm_props.instance_type).to eq('Standard_D2_v3')
              end
            end
          end

          context 'when disk_cids are provided' do
            let(:disk_cid) { 'fake-disk-cid' }
            let(:disk_cids) { [disk_cid] }
            let(:disk_id_object) { instance_double(Bosh::AzureCloud::DiskId) }
            before do
              allow(Bosh::AzureCloud::DiskId).to receive(:parse)
                .with(disk_cid, MOCK_RESOURCE_GROUP_NAME)
                .and_return(disk_id_object)
            end

            let(:available_vm_sizes) do
              [
                {
                  name: 'Standard_DS2_v3',
                  number_of_cores: '2',
                  memory_in_mb: 4096
                },
                {
                  name: 'Standard_D2_v3',
                  number_of_cores: '2',
                  memory_in_mb: 4096
                }
              ]
            end

            before do
              # Assume all vm sizes are available in the avset. These cases don't care about it.
              allow(azure_client).to receive(:list_available_virtual_machine_sizes_by_availability_set)
                .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                .and_return(available_vm_sizes)
            end

            context 'when the disk is a managed disk' do
              context 'when the disk is Standand SKU' do
                let(:disk) do
                  {
                    sku_tier: 'Standard'
                  }
                end
                before do
                  allow(disk_manager2).to receive(:get_data_disk)
                    .with(disk_id_object)
                    .and_return(disk)
                end

                it 'should select the first one of instance_types' do
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                  expect(vm_params[:name]).to eq(vm_name)
                  expect(vm_props.instance_type).to eq('Standard_DS2_v3')
                end

                context 'when instance_types do not support premium storage' do
                  let(:instance_types) { %w[Standard_D2_v3 Standard_D2_v2] }
                  let(:vm_props) do
                    props_factory.parse_vm_props(
                      'instance_type' => nil,
                      'instance_types' => instance_types,
                      'availability_set' => availability_set_name,
                      'platform_update_domain_count' => platform_update_domain_count,
                      'platform_fault_domain_count' => platform_fault_domain_count
                    )
                  end

                  it 'should select the first one of instance_types' do
                    expect(vm_manager2).to receive(:flock)
                      .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                      .and_call_original
                    expect(vm_manager2).to receive(:flock)
                      .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                      .and_call_original
                    expect(azure_client).to receive(:create_network_interface).twice

                    _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                    expect(vm_params[:name]).to eq(vm_name)
                    expect(vm_props.instance_type).to eq('Standard_D2_v3')
                  end
                end
              end

              context 'when the disk is Premium SKU' do
                let(:disk) do
                  {
                    sku_tier: 'Premium'
                  }
                end
                before do
                  allow(disk_manager2).to receive(:get_data_disk)
                    .with(disk_id_object)
                    .and_return(disk)
                end

                it 'should select one instance type which supports Premium storage' do
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                  expect(vm_params[:name]).to eq(vm_name)
                  expect(vm_props.instance_type).to eq('Standard_DS2_v3')
                end

                context 'when instance_types do not support premium storage' do
                  let(:instance_types) { %w[Standard_D2_v3 Standard_D2_v2] }
                  let(:vm_props) do
                    props_factory.parse_vm_props(
                      'instance_type' => nil,
                      'instance_types' => instance_types,
                      'availability_set' => availability_set_name,
                      'platform_update_domain_count' => platform_update_domain_count,
                      'platform_fault_domain_count' => platform_fault_domain_count
                    )
                  end

                  before do
                    allow(azure_client).to receive(:list_network_interfaces_by_keyword).and_return([])
                  end

                  it 'should raise an error' do
                    expect do
                      vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                    end.to raise_error(/No available instance type is found/)
                  end
                end
              end
            end

            context 'when the disk is an unmanaged disk' do
              context 'when the storage account is Standand SKU' do
                let(:storage_account_name) { 'fakestorageaccountname' }
                let(:storage_account) do
                  {
                    name: storage_account_name,
                    sku_tier: 'Standard'
                  }
                end
                before do
                  allow(disk_id_object).to receive(:storage_account_name)
                    .and_return(storage_account_name)
                  allow(azure_client).to receive(:get_storage_account_by_name)
                    .with(storage_account_name)
                    .and_return(storage_account)
                end

                it 'should select the first one of instance_types' do
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                  expect(vm_params[:name]).to eq(vm_name)
                  expect(vm_props.instance_type).to eq('Standard_DS2_v3')
                end

                context 'when instance_types do not support premium storage' do
                  let(:instance_types) { %w[Standard_D2_v3 Standard_D2_v2] }
                  let(:vm_props) do
                    props_factory.parse_vm_props(
                      'instance_type' => nil,
                      'instance_types' => instance_types,
                      'availability_set' => availability_set_name,
                      'platform_update_domain_count' => platform_update_domain_count,
                      'platform_fault_domain_count' => platform_fault_domain_count
                    )
                  end

                  it 'should select the first one of instance_types' do
                    expect(vm_manager).to receive(:flock)
                      .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                      .and_call_original
                    expect(vm_manager).to receive(:flock)
                      .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                      .and_call_original
                    expect(azure_client).to receive(:create_network_interface).twice

                    _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                    expect(vm_params[:name]).to eq(vm_name)
                    expect(vm_props.instance_type).to eq('Standard_D2_v3')
                  end
                end
              end

              context 'when the disk is Premium SKU' do
                let(:storage_account_name) { 'fakestorageaccountname' }
                let(:storage_account) do
                  {
                    name: storage_account_name,
                    sku_tier: 'Premium'
                  }
                end
                before do
                  allow(disk_id_object).to receive(:storage_account_name)
                    .and_return(storage_account_name)
                  allow(azure_client).to receive(:get_storage_account_by_name)
                    .with(storage_account_name)
                    .and_return(storage_account)
                end

                it 'should select one instance type which supports Premium storage' do
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                    .and_call_original
                  expect(vm_manager).to receive(:flock)
                    .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                    .and_call_original
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                  expect(vm_params[:name]).to eq(vm_name)
                  expect(vm_props.instance_type).to eq('Standard_DS2_v3')
                end

                context 'when instance_types do not support premium storage' do
                  let(:instance_types) { %w[Standard_D2_v3 Standard_D2_v2] }
                  let(:vm_props) do
                    props_factory.parse_vm_props(
                      'instance_type' => nil,
                      'instance_types' => instance_types,
                      'availability_set' => availability_set_name,
                      'platform_update_domain_count' => platform_update_domain_count,
                      'platform_fault_domain_count' => platform_fault_domain_count
                    )
                  end

                  before do
                    allow(azure_client).to receive(:list_network_interfaces_by_keyword).and_return([])
                  end

                  it 'should raise an error' do
                    expect do
                      vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                    end.to raise_error(/No available instance type is found/)
                  end
                end
              end
            end
          end
        end

        context 'with env is nil and availability_set is specified in vm_types or vm_extensions' do
          let(:env) { nil }
          let(:availability_set_name) { SecureRandom.uuid.to_s }
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'Standard_D1',
              'availability_set' => availability_set_name,
              'platform_update_domain_count' => 5,
              'platform_fault_domain_count' => 3
            )
          end
          let(:avset_params) do
            {
              name: vm_props.availability_set.name,
              location: location,
              tags: { 'user-agent' => 'bosh' },
              platform_update_domain_count: vm_props.availability_set.platform_update_domain_count,
              platform_fault_domain_count: vm_props.availability_set.platform_fault_domain_count,
              managed: false
            }
          end
          let(:availability_set) do
            {
              name: availability_set_name
            }
          end

          before do
            allow(azure_client).to receive(:get_availability_set_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
              .and_return(nil, availability_set)
          end

          it 'should create availability set with the name specified in vm_types or vm_extensions' do
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
              .and_call_original
            expect(vm_manager).to receive(:flock)
              .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
              .and_call_original

            expect(azure_client).to receive(:create_availability_set)
              .with(MOCK_RESOURCE_GROUP_NAME, avset_params)
            expect(azure_client).to receive(:create_network_interface).twice

            _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
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
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              )
            end
            let(:avset_params) do
              {
                name: vm_props.availability_set.name,
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: vm_props.availability_set.platform_update_domain_count,
                platform_fault_domain_count: vm_props.availability_set.platform_fault_domain_count,
                managed: false
              }
            end
            let(:availability_set) do
              {
                name: availability_set_name
              }
            end

            before do
              allow(azure_client).to receive(:get_availability_set_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                .and_return(nil, availability_set)
            end

            it 'should create availability set with the name specified in vm_types or vm_extensions' do
              expect(vm_manager).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                .and_call_original
              expect(vm_manager).to receive(:flock)
                .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                .and_call_original

              expect(azure_client).to receive(:create_availability_set)
                .with(MOCK_RESOURCE_GROUP_NAME, avset_params)

              _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context 'when availability_set is not specified in vm_types or vm_extensions' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1'
              )
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
                allow(azure_client).to receive(:get_availability_set_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, env['bosh']['group'])
                  .and_return(nil, availability_set)
              end

              it 'should create availability set and use value of env.bosh.group as its name' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{env['bosh']['group']}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{env['bosh']['group']}", File::LOCK_EX)
                  .and_call_original

                expect(azure_client).to receive(:create_availability_set)
                  .with(MOCK_RESOURCE_GROUP_NAME, avset_params)

                _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
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
                allow(azure_client).to receive(:get_availability_set_by_name)
                  .and_return(nil, availability_set)
              end

              it 'should create availability set with a truncated value of env.bosh.group as its name' do
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{avset_params[:name]}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{avset_params[:name]}", File::LOCK_EX)
                  .and_call_original

                expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)

                _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
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
            allow(azure_client).to receive(:get_availability_set_by_name)
              .with(MOCK_RESOURCE_GROUP_NAME, availability_set_name)
              .and_return(nil, availability_set)
          end

          context 'when platform_update_domain_count and platform_fault_domain_count are set' do
            let(:avset_params) do
              {
                name: vm_props.availability_set.name,
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 4,
                platform_fault_domain_count: 1
              }
            end

            context 'when the availability set is unmanaged' do
              let(:vm_props) do
                props_factory.parse_vm_props(
                  'instance_type' => 'Standard_D1',
                  'availability_set' => availability_set_name,
                  'platform_update_domain_count' => 4,
                  'platform_fault_domain_count' => 1
                )
              end
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

                expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                expect(azure_client).to receive(:create_network_interface).twice

                _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context 'when the availability set is managed' do
              let(:vm_props) do
                Bosh::AzureCloud::VMCloudProps.new(
                  {
                    'instance_type' => 'Standard_D1',
                    'availability_set' => availability_set_name,
                    'platform_update_domain_count' => 4,
                    'platform_fault_domain_count' => 1
                  }, azure_config_managed
                )
              end
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

                expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                expect(azure_client).to receive(:create_network_interface).twice

                _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end
          end

          context 'when platform_update_domain_count and platform_fault_domain_count are not set' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name
              )
            end
            let(:avset_params) do
              {
                name: vm_props.availability_set.name,
                location: location,
                tags: { 'user-agent' => 'bosh' }
              }
            end

            context 'when the environment is not AzureStack' do
              context 'when the availability set is unmanaged' do
                let(:vm_props) do
                  Bosh::AzureCloud::VMCloudProps.new(
                    {
                      'instance_type' => 'Standard_D1',
                      'availability_set' => availability_set_name
                    }, azure_config
                  )
                end
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

                  expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                  expect(vm_params[:name]).to eq(vm_name)
                end
              end

              context 'when the availability set is managed' do
                let(:vm_props) do
                  Bosh::AzureCloud::VMCloudProps.new(
                    {
                      'instance_type' => 'Standard_D1',
                      'availability_set' => availability_set_name
                    }, azure_config_managed
                  )
                end
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

                  expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
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
              let(:vm_manager_azure_stack) do
                Bosh::AzureCloud::VMManager.new(
                  azure_config_azure_stack, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager
                )
              end
              let(:vm_props) do
                Bosh::AzureCloud::VMCloudProps.new(
                  {
                    'instance_type' => 'Standard_D1',
                    'availability_set' => availability_set_name
                  },
                  azure_config_azure_stack
                )
              end

              before do
                allow(vm_manager_azure_stack).to receive(:_get_stemcell_info).and_return(stemcell_info)
                allow(vm_manager_azure_stack).to receive(:get_storage_account_from_vm_properties)
                  .and_return(name: storage_account_name)
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

                  expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                  expect(azure_client).to receive(:create_network_interface).twice

                  _, vm_params = vm_manager_azure_stack.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
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
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              )
            end

            before do
              allow(azure_client).to receive(:get_availability_set_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                .and_return(availability_set)
            end

            it 'should not create the availability set and then raise an error' do
              expect(azure_client).not_to receive(:create_availability_set)
              expect(azure_client).to receive(:delete_network_interface).exactly(2).times

              expect do
                vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
              end.to raise_error /availability set '#{availability_set_name}' already exists, but in a different location/
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
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name,
                'platform_update_domain_count' => 5,
                'platform_fault_domain_count' => 3
              )
            end

            before do
              allow(azure_client).to receive(:get_availability_set_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                .and_return(availability_set)
            end

            it 'should not create availability set' do
              expect(azure_client).not_to receive(:create_availability_set)

              _, vm_params = vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
              expect(vm_params[:name]).to eq(vm_name)
            end
          end

          context 'when the managed property is not aligned with @use_managed_disks' do
            let(:availability_set_name) { SecureRandom.uuid.to_s }
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'Standard_D1',
                'availability_set' => availability_set_name
              )
            end

            let(:existing_avset) do
              {
                name: vm_props.availability_set.name,
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 5,
                platform_fault_domain_count: 3,
                managed: false
              }
            end
            let(:existing_avset_managed) do
              {
                name: vm_props.availability_set.name,
                location: location,
                tags: { 'user-agent' => 'bosh' },
                platform_update_domain_count: 5,
                platform_fault_domain_count: 3,
                managed: true
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

            context 'existing avset is unmanaged' do
              before do
                allow(azure_client).to receive(:get_availability_set_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                  .and_return(existing_avset)
              end

              it 'should update the managed property of the availability set' do
                expect(vm_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_SH)
                  .and_call_original
                expect(vm_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_PREFIX_AVAILABILITY_SET}-#{availability_set_name}", File::LOCK_EX)
                  .and_call_original

                expect(azure_client).to receive(:create_availability_set).with(MOCK_RESOURCE_GROUP_NAME, avset_params)
                expect(azure_client).to receive(:create_network_interface).twice

                _, vm_params = vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                expect(vm_params[:name]).to eq(vm_name)
              end
            end

            context 'when using managed avset in unmanaged vm' do
              before do
                allow(azure_client).to receive(:get_availability_set_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, vm_props.availability_set.name)
                  .and_return(existing_avset_managed)
              end

              it 'should raise error' do
                expect(azure_client).to receive(:delete_network_interface).twice
                expect(azure_client).to receive(:create_network_interface).twice

                expect do
                  vm_manager.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
                end.to raise_error /availability set '.+' already exists. It's not allowed to update it from managed to unmanaged./
              end
            end
          end
        end
      end
    end
  end
end
