# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMManager do
  describe '#get_storage_account_from_vm_properties' do
    let(:props_factory) { Bosh::AzureCloud::PropsFactory.new(Bosh::AzureCloud::ConfigFactory.build(mock_cloud_options)) }
    let(:azure_config) { mock_azure_config }
    let(:registry_endpoint) { mock_registry.endpoint }
    let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
    let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
    let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
    let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_config, blob_manager, azure_client) }
    let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
    let(:stemcell_manager) { instance_double(Bosh::AzureCloud::StemcellManager) }
    let(:stemcell_manager2) { instance_double(Bosh::AzureCloud::StemcellManager2) }
    let(:light_stemcell_manager) { instance_double(Bosh::AzureCloud::LightStemcellManager) }
    let(:vm_manager) { Bosh::AzureCloud::VMManager.new(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager) }
    let(:location) { 'fake-location' }
    let(:default_storage_account) do
      {
        name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    end
    before do
      allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    let(:storage_account_name) { 'fake-storage-account-name-in-resource-pool' }
    let(:storage_account) do
      {
        name: storage_account_name
      }
    end

    context 'when vm_properties does not contain storage_account_name' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'fake-vm-size'
        )
      end

      it 'should return the default storage account' do
        expect(
          vm_manager.get_storage_account_from_vm_properties(vm_props, location)
        ).to be(default_storage_account)
      end
    end

    context 'when vm_properties contains storage_account_name' do
      context 'when the storage account name is not a pattern' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'fake-vm-size',
            'storage_account_name' => storage_account_name,
            'storage_account_type' => 'fake-storage_account_type',
            'storage_account_kind' => 'StorageV2',
            'storage_https_traffic' => true
          )
        end

        it 'should try to get or create the storage account' do
          expect(storage_account_manager).to receive(:get_or_create_storage_account)
            .with(storage_account_name, {}, 'fake-storage_account_type', 'StorageV2', location, %w[bosh stemcell], false, true)
            .and_return(storage_account)
          expect(
            vm_manager.get_storage_account_from_vm_properties(vm_props, location)
          ).to be(storage_account)
        end
      end

      context 'when the storage account name is a pattern' do
        context 'when the pattern is valid' do
          let(:vm_props) do
            props_factory.parse_vm_props(
              'instance_type' => 'fake-vm-size',
              'storage_account_name' => '*pattern*'
            )
          end
          let(:storage_accounts) do
            [
              {
                name: 'pattern',
                location: 'fake-location'
              }, {
                name: '2pattern',
                location: 'fake-location'
              }, {
                name: 'pattern3',
                location: 'fake-location'
              }, {
                name: '4pattern4',
                location: 'fake-location'
              }, {
                name: 'tpattern',
                location: 'fake-location'
              }, {
                name: 'patternt',
                location: 'fake-location'
              }, {
                name: 'tpatternt',
                location: 'fake-location'
              }, {
                name: 'patten',
                location: 'fake-location'
              }, {
                name: 'foo',
                location: 'fake-location'
              }
            ]
          end

          context 'when finding an availiable storage account successfully' do
            let(:disks) do
              [
                1, 2, 3
              ]
            end

            before do
              allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
              allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
            end

            context 'without storage_account_max_disk_number' do
              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should not raise any error' do
                expect(azure_client).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                vm_manager.get_storage_account_from_vm_properties(vm_props, location)
              end
            end

            context 'with 2 as storage_account_max_disk_number' do
              let(:vm_props) do
                props_factory.parse_vm_props(
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern*',
                  'storage_account_max_disk_number' => 2
                )
              end

              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
                allow(disk_manager).to receive(:list_disks).with('4pattern4').and_return([])
              end

              it 'should return an available storage account whose disk number is smaller than storage_account_max_disk_number' do
                expect(azure_client).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                expect(
                  vm_manager.get_storage_account_from_vm_properties(vm_props, location)
                ).to eq(
                  name: '4pattern4',
                  location: 'fake-location'
                )
              end
            end
          end

          context 'when cannot find an availiable storage account' do
            context 'when cannot find a storage account by the pattern' do
              let(:storage_accounts) { [] }

              before do
                allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
              end

              it 'should raise an error' do
                expect(azure_client).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect do
                  vm_manager.get_storage_account_from_vm_properties(vm_props, location)
                end.to raise_error(/get_storage_account_from_vm_properties - Cannot find an available storage account./)
              end
            end

            context 'when the disk number of every storage account is more than the limitation' do
              let(:disks) { (1..31).to_a }

              before do
                allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should raise an error' do
                expect(azure_client).not_to receive(:create_storage_account)

                expect do
                  vm_manager.get_storage_account_from_vm_properties(vm_props, location)
                end.to raise_error(/get_storage_account_from_vm_properties - Cannot find an available storage account./)
              end
            end
          end
        end

        context 'when the pattern is invalid' do
          context 'when the pattern contains one asterisk' do
            context 'when the pattern starts with one asterisk' do
              let(:vm_props) do
                props_factory.parse_vm_props(
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern'
                )
              end

              it 'should raise an error' do
                expect(azure_client).not_to receive(:list_storage_accounts)
                expect(azure_client).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect do
                  vm_manager.get_storage_account_from_vm_properties(vm_props, location)
                end.to raise_error(/get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid./)
              end
            end

            context 'when the pattern ends with one asterisk' do
              let(:vm_props) do
                props_factory.parse_vm_props(
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => 'pattern*'
                )
              end

              it 'should raise an error' do
                expect(azure_client).not_to receive(:list_storage_accounts)
                expect(azure_client).not_to receive(:create_storage_account)
                expect(azure_client).not_to receive(:get_storage_account_by_name)
                expect(disk_manager).not_to receive(:list_disks)

                expect do
                  vm_manager.get_storage_account_from_vm_properties(vm_props, location)
                end.to raise_error(/get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid./)
              end
            end
          end

          context 'when the pattern contains more than two asterisks' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '**pattern*'
              )
            end

            it 'should raise an error' do
              expect(azure_client).not_to receive(:list_storage_accounts)
              expect(azure_client).not_to receive(:create_storage_account)
              expect(azure_client).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect do
                vm_manager.get_storage_account_from_vm_properties(vm_props, location)
              end.to raise_error(/get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid./)
            end
          end

          context 'when the pattern contains upper-case letters' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*PATTERN*'
              )
            end

            it 'should raise an error' do
              expect(azure_client).not_to receive(:list_storage_accounts)
              expect(azure_client).not_to receive(:create_storage_account)
              expect(azure_client).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect do
                vm_manager.get_storage_account_from_vm_properties(vm_props, location)
              end.to raise_error(/get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid./)
            end
          end

          context 'when the pattern contains special characters' do
            let(:vm_props) do
              props_factory.parse_vm_props(
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*pat+tern*'
              )
            end

            it 'should raise an error' do
              expect(azure_client).not_to receive(:list_storage_accounts)
              expect(azure_client).not_to receive(:create_storage_account)
              expect(azure_client).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect do
                vm_manager.get_storage_account_from_vm_properties(vm_props, location)
              end.to raise_error(/get_storage_account_from_vm_properties - storage_account_name in vm_types or vm_extensions is invalid./)
            end
          end
        end
      end
    end
  end
end
