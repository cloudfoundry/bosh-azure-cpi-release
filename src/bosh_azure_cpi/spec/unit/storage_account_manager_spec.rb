require 'spec_helper'

describe Bosh::AzureCloud::StorageAccountManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_properties, blob_manager, disk_manager, client2) }
  let(:azure_client) { instance_double(Azure::Storage::Client) }

  before do
    allow(Azure::Storage::Client).to receive(:create).
      and_return(azure_client)
    allow(azure_client).to receive(:storage_table_host)
  end

  describe '#create_storage_account' do
    # Parameters
    let(:storage_account_name) { "fake-storage-account-name" }
    let(:storage_account_location) { "fake-storage-account-location" }
    let(:storage_account_type) { "fake-storage-account-type" }
    let(:tags) { {"foo" => "bar"} }

    context 'when the storage account name is invalid' do
      let(:result) {
        {
          :available => false,
          :reason => 'AccountNameInvalid',
          :message => 'fake-message'
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
      end

      it 'should raise an error' do
        expect {
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        }.to raise_error(/The storage account name `#{storage_account_name}' is invalid./)
      end
    end

    context 'when the storage account name is available' do
      let(:result) {
        {
          :available => true
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
      end

      it 'should create the storage account' do
        expect(client2).to receive(:create_storage_account).with(storage_account_name, storage_account_location, storage_account_type, tags)
        expect(blob_manager).to receive(:prepare).with(storage_account_name, {:is_default_storage_account=>false})

        expect(
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        ).to be(true)
      end
    end

    context 'when the storage account is default storage account' do
      let(:result) {
        {
          :available => true
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
      end

      it 'should create the storage account, and set the acl of the stemcell container to public' do
        expect(client2).to receive(:create_storage_account).with(storage_account_name, storage_account_location, storage_account_type, tags)
        expect(blob_manager).to receive(:prepare).with(storage_account_name, {:is_default_storage_account=>true})

        expect(
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags, true)
        ).to be(true)
      end
    end

    context 'when the storage account is not default storage account' do
      let(:result) {
        {
          :available => true
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
      end

      it 'should create the storage account, and do not set the acl' do
        expect(client2).to receive(:create_storage_account).with(storage_account_name, storage_account_location, storage_account_type, tags)
        expect(blob_manager).to receive(:prepare).with(storage_account_name, {:is_default_storage_account=>false})

        expect(
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        ).to be(true)
      end
    end

    context 'when storage_account_location is not specified' do
      let(:storage_account_location) { nil }
      let(:result) {
        {
          :available => true
        }
      }
      let(:resource_group_location) { "fake-resource-group-location" }
      let(:resource_group) {
        {
          :name => "fake-rg-name",
          :location => resource_group_location
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
        allow(client2).to receive(:get_resource_group).and_return(resource_group)
      end

      it 'should create the storage account in the location of the resource group' do
        expect(client2).to receive(:create_storage_account).with(storage_account_name, resource_group_location, storage_account_type, tags)
        expect(blob_manager).to receive(:prepare).with(storage_account_name, {:is_default_storage_account=>false})

        expect(
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        ).to be(true)
      end
    end

    context 'when the same storage account is being created by others' do
      let(:result) {
        {
          :available => false,
          :reason => 'AlreadyExists',
          :message => 'fake-message'
        }
      }
      let(:storage_account) {
        {
          :id => "foo",
          :name => storage_account_name,
          :location => "bar",
          :provisioning_state => "Succeeded",
          :account_type => "foo",
          :storage_blob_host => "fake-blob-endpoint",
          :storage_table_host => "fake-table-endpoint"
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
        allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(storage_account)
      end

      it 'should create the storage account' do
        expect(blob_manager).to receive(:prepare).with(storage_account_name, {:is_default_storage_account=>false})

        expect(
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        ).to be(true)
      end
    end

    context 'when the storage account belongs to other resource group' do
      let(:result) {
        {
          :available => false,
          :reason => 'AlreadyExists',
          :message => 'fake-message'
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
        allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(nil)
      end

      it 'should create the storage account' do
        expect(blob_manager).not_to receive(:prepare)

        expect {
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        }.to raise_error(/The storage account with the name `fake-storage-account-name' does not belong to the resource group `#{MOCK_RESOURCE_GROUP_NAME}'./)
      end
    end

    context 'when the storage account cannot be created' do
      let(:result) { { :available => true } }
      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
        allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(nil)
        allow(client2).to receive(:create_storage_account).and_raise(StandardError)
      end

      it 'should raise an error' do
        expect(blob_manager).not_to receive(:prepare)

        expect {
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        }.to raise_error(/create_storage_account - Error/)
      end
    end

    context 'when the container cannot be created' do
      let(:result) { { :available => true } }
      let(:storage_account) {
        {
          :id => "foo",
          :name => storage_account_name,
          :location => "bar",
          :provisioning_state => "Succeeded",
          :account_type => "foo",
          :storage_blob_host => "fake-blob-endpoint",
          :storage_table_host => "fake-table-endpoint"
        }
      }

      before do
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).and_return(result)
        allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(storage_account)
        allow(client2).to receive(:create_storage_account).and_return(true)
        allow(blob_manager).to receive(:prepare).and_raise(StandardError)
      end

      it 'should raise an error' do
        expect(client2).to receive(:create_storage_account)

        expect {
          storage_account_manager.create_storage_account(storage_account_name, storage_account_type, storage_account_location, tags)
        }.to raise_error(/The storage account `fake-storage-account-name' is created successfully.\nBut it failed to prepare the containers/)
      end
    end
  end

  describe '#get_storage_account_from_resource_pool' do
    let(:default_storage_account) {
      {
        :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    }
    let(:storage_account_name) { 'fake-storage-account-name-in-resource-pool' }
    let(:storage_account) {
      {
        :name => storage_account_name
      }
    }

    context 'when resource_pool does not contain storage_account_name' do
      let(:resource_pool) {
        {
          'instance_type' => 'fake-vm-size'
        }
      }

      before do
        allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
      end

      it 'should return the default storage account' do
        storage_account_manager.default_storage_account_name()

        expect(
          storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
        ).to be(default_storage_account)
      end
    end

    context 'when resource_pool contains storage_account_name' do
      context 'when the storage account name is not a pattern' do
        let(:resource_pool) {
          {
            'instance_type' => 'fake-vm-size',
            'storage_account_name' => storage_account_name
          }
        }

        context 'when the storage account exists' do
          before do
            allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
            allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(storage_account)
          end

          it 'should return the existing storage account' do
            storage_account_manager.default_storage_account_name()

            expect(
              storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
            ).to be(storage_account)
          end
        end

        context 'when the storage account does not exist' do
          before do
            allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
            allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(nil)
          end

          context 'when resource_pool does not contain storage_account_type' do
            it 'should raise an error' do
              storage_account_manager.default_storage_account_name()

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
              }.to raise_error(/missing required cloud property `storage_account_type'/)
            end
          end
        end
      end

      context 'when the storage account name is a pattern' do
        context 'when the pattern is valid' do
          let(:resource_pool) {
            {
              'instance_type' => 'fake-vm-size',
              'storage_account_name' => '*pattern*'
            }
          }
          let(:storage_accounts) {
            [
              {
                :name => 'pattern',
                :location => 'fake-location'
              }, {
                :name => '2pattern',
                :location => 'fake-location'
              }, {
                :name => 'pattern3',
                :location => 'fake-location'
              }, {
                :name => '4pattern4',
                :location => 'fake-location'
              }, {
                :name => 'tpattern',
                :location => 'fake-location'
              }, {
                :name => 'patternt',
                :location => 'fake-location'
              }, {
                :name => 'tpatternt',
                :location => 'fake-location'
              }, {
                :name => 'patten',
                :location => 'fake-location'
              }, {
                :name => 'foo',
                :location => 'fake-location'
              }
            ]
          }

          context 'when finding an availiable storage account successfully' do
            let(:disks) {
              [
                1,2,3
              ]
            }

            before do
              allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            end

            context 'without storage_account_max_disk_number' do
              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should not raise any error' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
              end
            end

            context 'with 2 as storage_account_max_disk_number' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern*',
                  'storage_account_max_disk_number' => 2
                }
              }

              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
                allow(disk_manager).to receive(:list_disks).with('4pattern4').and_return([])
              end

              it 'should return an available storage account whose disk number is smaller than storage_account_max_disk_number' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                expect(
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
                ).to eq(
                  {
                    :name => '4pattern4',
                    :location => 'fake-location'
                  }
                )
              end
            end
          end

          context 'when cannot find an availiable storage account' do
            context 'when cannot find a storage account by the pattern' do
              let(:storage_accounts) { [] }

              before do
                allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              end

              it 'should raise an error' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
                }.to raise_error(/get_storage_account_from_resource_pool - Cannot find an available storage account./)
              end
            end

            context 'when the disk number of every storage account is more than the limitation' do
              let(:disks) { (1..31).to_a }

              before do
                allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should raise an error' do
                expect(client2).not_to receive(:create_storage_account)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
                }.to raise_error(/get_storage_account_from_resource_pool - Cannot find an available storage account./)
              end
            end
          end
        end

        context 'when the pattern is invalid' do
          context 'when the pattern contains one asterisk' do
            context 'when the pattern starts with one asterisk' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern'
                }
              }

              it 'should raise an error' do
                expect(client2).not_to receive(:list_storage_accounts)
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
                }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
              end
            end

            context 'when the pattern ends with one asterisk' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => 'pattern*'
                }
              }

              it 'should raise an error' do
                expect(client2).not_to receive(:list_storage_accounts)
                expect(client2).not_to receive(:create_storage_account)
                expect(client2).not_to receive(:get_storage_account_by_name)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
                }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
              end
            end
          end

          context 'when the pattern contains more than two asterisks' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '**pattern*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end

          context 'when the pattern contains upper-case letters' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*PATTERN*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end

          context 'when the pattern contains special characters' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*pat+tern*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end
        end
      end
    end
  end

  describe '#default_storage_account' do
    let(:default_storage_account) {
      {
        :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    }
    before do
      allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    context 'When the global configurations contain storage_account_name' do
      context 'When use_managed_disks is false' do
        it 'should return the default storage account, and do not set the tags' do
          expect(client2).not_to receive(:update_tags_of_storage_account)
          expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
        end
      end

      context 'When use_managed_disks is true' do
        let(:azure_properties_managed) {
          mock_azure_properties_merge({
            'use_managed_disks' => true
          })
        }
        let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_properties_managed, blob_manager, disk_manager, client2) }

        context 'When the default storage account do not have the tags' do
          it 'should return the default storage account, and set the tags' do
            expect(client2).to receive(:update_tags_of_storage_account).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, STEMCELL_STORAGE_ACCOUNT_TAGS)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end

        context 'When the default storage account has the tags' do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
            }
          }
          before do
            allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
          end

          it 'should return the default storage account, and do not set the tags' do
            expect(client2).not_to receive(:update_tags_of_storage_account)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end
      end
    end

    context 'When the global configurations do not contain storage_account_name' do
      let(:tags) {
        {
          'user-agent' => 'bosh',
          'type' => 'stemcell'
        }
      }
      let(:resource_group_location) { 'fake-resource-group-location' }
      let(:resource_group) {
        {
          :name => "fake-rg-name",
          :location => resource_group_location
        }
      }

      context 'When the storage account with the specified tags is found in the resource group location' do
        let(:targeted_storage_account) {
          {
            :name => 'account1',
            :location => resource_group_location,
            :tags => tags
          }
        }
        let(:storage_accounts) {
          [
            targeted_storage_account,
            {
              :name => 'account2',
              :location => resource_group_location,
              :tags => {}
            },
            {
              :name => 'account3',
              :location => 'different-location',
              :tags => tags
            }
          ]
        }
        before do
          allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
          allow(client2).to receive(:get_resource_group).and_return(resource_group)
        end

        it 'should return the storage account' do
          azure_properties.delete('storage_account_name')
          expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)

          expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
        end
      end

      context 'When the storage account with the specified tags is not found in the resource group location' do
        let(:request_id) { 'fake-client-request-id' }
        let(:options) {
          {
            :request_id => request_id
          }
        }
        let(:azure_client) { instance_double(Azure::Storage::Client) }
        let(:table_service) { instance_double(Azure::Storage::Table::TableService) }
        let(:exponential_retry) { instance_double(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter) }

        before do
          allow(azure_client).to receive(:storage_table_host=)
          allow(azure_client).to receive(:table_client).
            and_return(table_service)
          allow(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter).to receive(:new).
            and_return(exponential_retry)
          allow(table_service).to receive(:with_filter).with(exponential_retry)
          allow(SecureRandom).to receive(:uuid).and_return(request_id)
        end

        context 'When the old storage account with the stemcell table is found in the resource group' do
          before do
            allow(table_service).to receive(:get_table).
              with('stemcells', options)
          end

          context 'When the old storage account is in the resource group location' do
            let(:targeted_storage_account) {
              {
                :name => 'account1',
                :location => resource_group_location,
                :account_type => 'Standard_LRS',
                :storage_table_host => 'fake-host'
              }
            }
            let(:storage_accounts) {
              [
                targeted_storage_account
              ]
            }
            let(:keys) { ['fake-key-1', 'fake-key-2'] }

            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(client2).to receive(:get_resource_group).and_return(resource_group)
              allow(client2).to receive(:get_storage_account_by_name).
                with(targeted_storage_account[:name]).
                and_return(targeted_storage_account)
              allow(client2).to receive(:get_storage_account_keys_by_name).
                with(targeted_storage_account[:name]).
                and_return(keys)
              allow(Azure::Storage::Client).to receive(:create).
                with({
                  :storage_account_name => targeted_storage_account[:name],
                  :storage_access_key => keys[0],
                  :user_agent_prefix=>"BOSH-AZURE-CPI"
                }).and_return(azure_client)
            end

            it 'should return the storage account' do
              azure_properties.delete('storage_account_name')
              expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
              expect(client2).to receive(:update_tags_of_storage_account).with(targeted_storage_account[:name], tags)
  
              expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
            end
          end

          context 'When the old storage account is not in the resource group location' do
            let(:targeted_storage_account) {
              {
                :name => 'account1',
                :location => 'another-resource-group-location',
                :account_type => 'Standard_LRS',
                :storage_table_host => 'fake-host'
              }
            }
            let(:storage_accounts) {
              [
                targeted_storage_account
              ]
            }
            let(:keys) { ['fake-key-1', 'fake-key-2'] }

            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(client2).to receive(:get_resource_group).and_return(resource_group)
              allow(client2).to receive(:get_storage_account_by_name).
                with(targeted_storage_account[:name]).
                and_return(targeted_storage_account)
              allow(client2).to receive(:get_storage_account_keys_by_name).
                with(targeted_storage_account[:name]).
                and_return(keys)
              allow(Azure::Storage::Client).to receive(:create).
                with({
                  :storage_account_name => targeted_storage_account[:name],
                  :storage_access_key => keys[0],
                  :user_agent_prefix=>"BOSH-AZURE-CPI"
                }).and_return(azure_client)
            end

            it 'should raise an error' do
              azure_properties.delete('storage_account_name')

              expect {
                storage_account_manager.default_storage_account
              }.to raise_error(/The existing default storage account `#{targeted_storage_account[:name]}' has a different location other than the resource group location./)
            end
          end
        end

        context 'When no standard storage account is found in the resource group' do
          let(:targeted_storage_account) {
            {
              :name => 'account1',
              :location => resource_group_location,
              :account_type => 'Premium_LRS',
              :storage_table_host => 'fake-host'
            }
          }
          let(:storage_accounts) {
            [
              targeted_storage_account
            ]
          }

          before do
            allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(client2).to receive(:get_resource_group).and_return(resource_group)
            allow(client2).to receive(:get_storage_account_by_name).
              with(targeted_storage_account[:name]).
              and_return(targeted_storage_account)
          end

          let(:result) {
            {
              :available => true
            }
          }
          let(:random_postfix) { SecureRandom.hex(12) }
          let(:new_storage_account_name) { "#{random_postfix}" }

          before do
            allow(SecureRandom).to receive(:hex).and_return(random_postfix)
            allow(client2).to receive(:check_storage_account_name_availability).with(new_storage_account_name).and_return(result)
            allow(blob_manager).to receive(:prepare).with(new_storage_account_name, {:is_default_storage_account=>true})
          end

          it 'should create a new storage account' do
            azure_properties.delete('storage_account_name')
            expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
            expect(client2).to receive(:create_storage_account)
            expect(client2).to receive(:get_storage_account_by_name).with(new_storage_account_name)

            storage_account_manager.default_storage_account
          end
        end

        context 'When the old storage account with the stemcell table is not found in the resource group' do
          let(:targeted_storage_account) {
            {
              :name => 'account1',
              :location => resource_group_location,
              :account_type => 'Standard_LRS',
              :storage_table_host => 'fake-host'
            }
          }
          let(:storage_accounts) {
            [
              targeted_storage_account
            ]
          }
          let(:keys) { ['fake-key-1', 'fake-key-2'] }

          before do
            allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(client2).to receive(:get_resource_group).and_return(resource_group)
            allow(client2).to receive(:get_storage_account_by_name).
              with(targeted_storage_account[:name]).
              and_return(targeted_storage_account)
            allow(client2).to receive(:get_storage_account_keys_by_name).
              with(targeted_storage_account[:name]).
              and_return(keys)
            allow(Azure::Storage::Client).to receive(:create).
              with({
                :storage_account_name => targeted_storage_account[:name],
                :storage_access_key => keys[0],
                :user_agent_prefix=>"BOSH-AZURE-CPI"
              }).and_return(azure_client)
            allow(table_service).to receive(:get_table).
              and_raise("(404)") # The table stemcells is not found in the storage account
          end

          let(:result) {
            {
              :available => true
            }
          }
          let(:random_postfix) { SecureRandom.hex(12) }
          let(:new_storage_account_name) { "#{random_postfix}" }

          before do
            allow(SecureRandom).to receive(:hex).and_return(random_postfix)
            allow(client2).to receive(:check_storage_account_name_availability).with(new_storage_account_name).and_return(result)
            allow(blob_manager).to receive(:prepare).with(new_storage_account_name, {:is_default_storage_account=>true})
          end

          it 'should create a new storage account' do
            azure_properties.delete('storage_account_name')
            expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
            expect(client2).to receive(:create_storage_account)
            expect(client2).to receive(:get_storage_account_by_name).with(new_storage_account_name)

            storage_account_manager.default_storage_account
          end
        end
      end

      context 'When no storage account is found in the resource group location' do
        let(:result) {
          {
            :available => true
          }
        }
        let(:random_postfix) { SecureRandom.hex(12) }
        let(:new_storage_account_name) { "#{random_postfix}" }

        before do
          allow(client2).to receive(:list_storage_accounts).and_return([])
          allow(client2).to receive(:get_resource_group).and_return(resource_group)
          allow(SecureRandom).to receive(:hex).and_return(random_postfix)
          allow(client2).to receive(:check_storage_account_name_availability).with(new_storage_account_name).and_return(result)
          allow(blob_manager).to receive(:prepare).with(new_storage_account_name, {:is_default_storage_account=>true})
        end

        it 'should create a new storage account' do
          azure_properties.delete('storage_account_name')
          expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
          expect(client2).to receive(:create_storage_account)
          expect(client2).to receive(:get_storage_account_by_name).with(new_storage_account_name)

          storage_account_manager.default_storage_account
        end
      end
    end
  end
end
