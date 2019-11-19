# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::StorageAccountManager do
  let(:azure_config) { mock_azure_config }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_config, blob_manager, azure_client) }
  let(:azure_storage_client) { instance_double(Azure::Storage::Client) }
  let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }

  before do
    allow(Azure::Storage::Client).to receive(:create)
      .and_return(azure_storage_client)
    allow(azure_storage_client).to receive(:storage_table_host)
  end

  describe '#generate_storage_account_name' do
    context 'when the first generated name is available' do
      let(:storage_account_name) { '386ebba59c883c7d15b419b3' }
      before do
        allow(SecureRandom).to receive(:hex).with(12).and_return(storage_account_name)
        allow(azure_client).to receive(:check_storage_account_name_availability).with(storage_account_name)
                                                                                .and_return(
                                                                                  available: true
                                                                                )
      end

      it 'should return the available storage account name' do
        expect(azure_client).to receive(:check_storage_account_name_availability).once
        expect(storage_account_manager.generate_storage_account_name).to eq(storage_account_name)
      end
    end

    context 'when the first generated name is not available, and the second one is available' do
      let(:storage_account_name_unavailable) { '386ebba59c883c7d15b419b3' }
      let(:storage_account_name_available)   { 'db49daf2fbbf100575a3af9c' }
      before do
        allow(SecureRandom).to receive(:hex).with(12).and_return(storage_account_name_unavailable, storage_account_name_available)
        allow(azure_client).to receive(:check_storage_account_name_availability).with(storage_account_name_unavailable)
                                                                                .and_return(
                                                                                  available: false
                                                                                )
        allow(azure_client).to receive(:check_storage_account_name_availability).with(storage_account_name_available)
                                                                                .and_return(
                                                                                  available: true
                                                                                )
      end

      it 'should return the available storage account name' do
        expect(azure_client).to receive(:check_storage_account_name_availability).twice
        expect(storage_account_manager.generate_storage_account_name).to eq(storage_account_name_available)
      end
    end
  end

  describe '#get_or_create_storage_account' do
    # Parameters
    let(:name) { 'fake-storage-account-name' }
    let(:location) { 'fake-storage-account-location' }
    let(:type) { 'fake-storage-account-type' }
    let(:kind) { 'Storage' }
    let(:tags) { { 'foo' => 'bar' } }
    let(:containers) { %w[bosh stemcell] }
    let(:is_default_storage_account) { false }

    let(:storage_account) { double('storage-account') }

    before do
      expect(storage_account_manager).to receive(:flock)
        .with("#{CPI_LOCK_PREFIX_STORAGE_ACCOUNT}-#{name}", File::LOCK_EX)
        .and_call_original
    end

    context 'when the storage account is already created by other process' do
      before do
        expect(storage_account_manager).to receive(:find_storage_account_by_name)
          .and_return(storage_account)
      end

      it 'should return the storage account' do
        expect(
          storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
        ).to be(storage_account)
      end
    end

    context 'if the storage account is going to be created' do
      context 'when the storage account name is invalid' do
        let(:result) do
          {
            available: false,
            reason: 'AccountNameInvalid',
            message: 'fake-message'
          }
        end
        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/The storage account name '#{name}' is invalid./)
        end
      end

      context 'when the storage account is not available' do
        let(:result) do
          {
            available: false,
            reason: 'fake-reason',
            message: 'fake-message'
          }
        end
        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/The storage account with the name '#{name}' is not available/)
        end
      end

      context 'when name is not nil' do
        let(:result) { { available: true } }
        let(:name) { nil }

        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/Require name to create a new storage account/)
        end
      end

      context 'when type is not provided' do
        let(:result) { { available: true } }
        let(:type) { nil }

        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/Require type to create a new storage account/)
        end
      end

      context 'when location not provided' do
        let(:result) { { available: true } }
        let(:location) { nil }

        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/Require location to create a new storage account/)
        end
      end

      context 'when everything is ok' do
        let(:result) { { available: true } }

        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil, storage_account)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
        end

        it 'should create the storage account' do
          expect(azure_client).to receive(:create_storage_account)
            .with(name, location, type, kind, tags)
          expect(
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          ).to be(storage_account)
        end
      end

      context 'when the storage account is not found after creating' do
        let(:result) { { available: true } }

        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil, nil)
          allow(azure_client).to receive(:check_storage_account_name_availability).with(name).and_return(result)
          allow(azure_client).to receive(:create_storage_account)
            .with(name, location, type, kind, tags)
            .and_return(true)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.get_or_create_storage_account(name, tags, type, kind, location, containers, is_default_storage_account)
          end.to raise_error(/Storage account '#{name}' is not created/)
        end
      end
    end
  end

  describe '#get_or_create_storage_account_by_tags' do
    let(:tags) { { 'key' => 'value' } }
    let(:type) { 'fake-type' }
    let(:kind) { 'Storage' }
    let(:location) { 'fake-location' }
    let(:containers) { ['bosh'] }
    let(:is_default_storage_account) { false }
    let(:storage_account) { { name: 'fake-name' } }

    before do
      expect(storage_account_manager).to receive(:flock)
        .with("#{CPI_LOCK_PREFIX_STORAGE_ACCOUNT}-#{location}-#{Digest::MD5.hexdigest(tags.to_s)}", File::LOCK_EX)
        .and_call_original
    end

    context 'when the storage account is already created' do
      before do
        allow(storage_account_manager).to receive(:find_storage_account_by_tags)
          .with(tags, location)
          .and_return(storage_account)
      end

      it 'should return the storage account directly' do
        expect(
          storage_account_manager.get_or_create_storage_account_by_tags(tags, type, kind, location, containers, is_default_storage_account)
        ).to be(storage_account)
      end
    end

    context 'when the storage account does not exist' do
      let(:name) { 'fake-name' }

      before do
        allow(storage_account_manager).to receive(:find_storage_account_by_tags)
          .with(tags, location)
          .and_return(nil)
        allow(storage_account_manager).to receive(:generate_storage_account_name)
          .and_return(name)
      end

      it 'should create a new storage account' do
        expect(storage_account_manager).to receive(:get_or_create_storage_account)
          .with(name, tags, type, kind, location, containers, is_default_storage_account)
          .and_return(storage_account)
        expect(
          storage_account_manager.get_or_create_storage_account_by_tags(tags, type, kind, location, containers, is_default_storage_account)
        ).to be(storage_account)
      end

      it 'should raise an error if it fails to get the storage account after creating' do
        expect(storage_account_manager).to receive(:get_or_create_storage_account)
          .with(name, tags, type, kind, location, containers, is_default_storage_account)
          .and_return(nil)
        expect do
          storage_account_manager.get_or_create_storage_account_by_tags(tags, type, kind, location, containers, is_default_storage_account)
        end.to raise_error(/Storage account for tags '#{tags}' is not created/)
      end

      it 'should raise an error if it fails to create a new storage account' do
        expect(storage_account_manager).to receive(:get_or_create_storage_account)
          .with(name, tags, type, kind, location, containers, is_default_storage_account)
          .and_raise('failed to create storage account')
        expect do
          storage_account_manager.get_or_create_storage_account_by_tags(tags, type, kind, location, containers, is_default_storage_account)
        end.to raise_error(/failed to create storage account/)
      end
    end
  end

  describe '#find_storage_account_by_name' do
    context 'when storage account exists' do
      let(:name) { 'fake-name' }
      let(:storage_account) { { name: 'fake-name' } }

      it 'get the storage account by name' do
        expect(azure_client).to receive(:get_storage_account_by_name)
          .with(name)
          .and_return(storage_account)
        expect(
          storage_account_manager.find_storage_account_by_name(name)
        ).to be(storage_account)
      end
    end

    context 'when storage account does not exist' do
      let(:name) { 'fake-name' }

      before do
        allow(azure_client).to receive(:get_storage_account_by_name).with(name).and_return(nil)
      end

      it 'should return nil' do
        expect(
          storage_account_manager.find_storage_account_by_name(name)
        ).to be(nil)
      end
    end
  end

  describe '#find_storage_account_by_tags' do
    let(:tags) { { 'key' => 'value' } }
    let(:location) { 'fake-location' }

    context 'when storage account exists' do
      let(:name) { 'fake-name' }
      let(:storage_account) do
        {
          name: name,
          location: location,
          tags: tags
        }
      end

      before do
        allow(azure_client).to receive(:list_storage_accounts)
          .and_return([storage_account])
      end

      it 'should return the storage account' do
        expect(
          storage_account_manager.find_storage_account_by_tags(tags, location)
        ).to be(storage_account)
      end
    end

    context 'when storage account does not exist' do
      let(:name) { 'fake-name' }
      let(:storage_account) do
        {
          name: name,
          location: location,
          tags: { 'x' => 'y' }
        }
      end

      before do
        allow(azure_client).to receive(:list_storage_accounts)
          .and_return([storage_account])
      end

      it 'should return nil' do
        expect(
          storage_account_manager.find_storage_account_by_tags(tags, location)
        ).to be(nil)
      end
    end
  end

  describe '#default_storage_account_name' do
    context 'When the global configurations contain storage_account_name' do
      it 'should return the storage account' do
        expect(storage_account_manager).not_to receive(:default_storage_account)
        expect(storage_account_manager.default_storage_account_name).to eq(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
      end
    end

    context 'When the global configurations do not contain storage_account_name' do
      it 'should return the storage account' do
        azure_config.storage_account_name = nil
        expect(storage_account_manager).to receive(:default_storage_account).and_return(name: 'default_storage_account')
        expect(storage_account_manager.default_storage_account_name).to eq('default_storage_account')
      end
    end
  end

  describe '#default_storage_account' do
    let(:default_storage_account) do
      {
        name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    end
    before do
      allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    context 'When the global configurations contain storage_account_name' do
      context 'when the storage account does not exist' do
        before do
          allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(nil)
        end

        it 'should raise an error' do
          expect do
            storage_account_manager.default_storage_account
          end.to raise_error /The default storage account '#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}' is specified in Global Configuration, but it does not exist./
        end
      end

      context 'When use_managed_disks is false' do
        it 'should return the default storage account, and do not set the tags' do
          expect(azure_client).not_to receive(:update_tags_of_storage_account)
          expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
        end
      end

      context 'When use_managed_disks is true' do
        let(:azure_config_managed) do
          mock_azure_config_merge(
            'use_managed_disks' => true
          )
        end
        let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_config_managed, blob_manager, azure_client) }

        context 'When the default storage account do not have the tags' do
          it 'should return the default storage account, and set the tags' do
            expect(azure_client).to receive(:update_tags_of_storage_account).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, STEMCELL_STORAGE_ACCOUNT_TAGS)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end

        context 'When the default storage account has the tags' do
          let(:default_storage_account) do
            {
              name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              tags: STEMCELL_STORAGE_ACCOUNT_TAGS
            }
          end
          before do
            allow(azure_client).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
          end

          it 'should return the default storage account, and do not set the tags' do
            expect(azure_client).not_to receive(:update_tags_of_storage_account)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end
      end
    end

    context 'When the global configurations do not contain storage_account_name' do
      context 'When the cache file contains the storage account name' do
        let(:cached_storage_account_name) { "fo9oasag36otw142bykc" }
        before do
          File.open(STORAGE_ACCOUNT_NAME_CACHE, 'w') { |file| file.write(cached_storage_account_name) }
        end
        after do
          File.delete(STORAGE_ACCOUNT_NAME_CACHE) if File.exist?(STORAGE_ACCOUNT_NAME_CACHE)
        end

        context 'when the storage account exists' do
          before do
            allow(azure_client).to receive(:get_storage_account_by_name).with(cached_storage_account_name).and_return(default_storage_account)
          end

          it 'should return the default storage account, and do not set the tags' do
            azure_config.storage_account_name = nil
            expect(azure_client).not_to receive(:update_tags_of_storage_account)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end

        context 'when the storage account does not exist' do
          let(:resource_group_location) { 'fake-resource-group-location' }
          let(:resource_group) do
            {
              name: 'fake-rg-name',
              location: resource_group_location
            }
          end
          let(:targeted_storage_account) do
            {
              name: 'account1',
              location: resource_group_location,
              tags: STEMCELL_STORAGE_ACCOUNT_TAGS
            }
          end
          let(:storage_accounts) do
            [
              targeted_storage_account,
            ]
          end
          before do
            allow(azure_client).to receive(:get_storage_account_by_name).with(cached_storage_account_name).and_return(nil)
            allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(azure_client).to receive(:get_resource_group)
              .with(default_resource_group_name)
              .and_return(resource_group)
          end

          it 'should list the storage accounts and select one' do
            azure_config.storage_account_name = nil 
            expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
          end
        end
      end

      context 'When the cache file does not contain the storage account name' do
        let(:resource_group_location) { 'fake-resource-group-location' }
        let(:resource_group) do
          {
            name: 'fake-rg-name',
            location: resource_group_location
          }
        end

        before do
          File.delete(STORAGE_ACCOUNT_NAME_CACHE) if File.exist?(STORAGE_ACCOUNT_NAME_CACHE)
        end

        context 'When the storage account with the specified tags is found in the resource group location' do
          let(:targeted_storage_account) do
            {
              name: 'account1',
              location: resource_group_location,
              tags: STEMCELL_STORAGE_ACCOUNT_TAGS
            }
          end
          let(:storage_accounts) do
            [
              targeted_storage_account,
              {
                name: 'account2',
                location: resource_group_location,
                tags: {}
              },
              {
                name: 'account3',
                location: 'different-location',
                tags: STEMCELL_STORAGE_ACCOUNT_TAGS
              }
            ]
          end
          before do
            allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(azure_client).to receive(:get_resource_group)
              .with(default_resource_group_name)
              .and_return(resource_group)
          end

          it 'should return the storage account' do
            azure_config.storage_account_name = nil
            expect(azure_client).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)

            expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
          end
        end

        context 'When the storage account with the specified tags is not found in the resource group location' do
          let(:request_id) { 'fake-client-request-id' }
          let(:options) do
            {
              request_id: request_id
            }
          end
          let(:azure_storage_client) { instance_double(Azure::Storage::Client) }
          let(:table_service) { instance_double(Azure::Storage::Table::TableService) }
          let(:exponential_retry) { instance_double(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter) }
          let(:storage_dns_suffix) { 'fake-storage-dns-suffix' }

          before do
            allow(azure_storage_client).to receive(:table_client)
              .and_return(table_service)
            allow(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter).to receive(:new)
              .and_return(exponential_retry)
            allow(table_service).to receive(:with_filter).with(exponential_retry)
            allow(SecureRandom).to receive(:uuid).and_return(request_id)
          end

          context 'When the old storage account with the stemcell table is found in the resource group' do
            before do
              allow(table_service).to receive(:get_table)
                .with('stemcells', options)
            end

            context 'When the old storage account is in the resource group location' do
              let(:targeted_storage_account) do
                {
                  name: 'account1',
                  location: resource_group_location,
                  sku_name: 'Standard_LRS',
                  sku_tier: 'Standard',
                  storage_blob_host: "https://account1.blob.#{storage_dns_suffix}",
                  storage_table_host: "https://account1.table.#{storage_dns_suffix}"
                }
              end
              let(:storage_accounts) do
                [
                  targeted_storage_account
                ]
              end
              let(:keys) { ['fake-key-1', 'fake-key-2'] }

              before do
                allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
                allow(azure_client).to receive(:get_resource_group)
                  .with(default_resource_group_name)
                  .and_return(resource_group)
                allow(azure_client).to receive(:get_storage_account_by_name)
                  .with(targeted_storage_account[:name])
                  .and_return(targeted_storage_account)
                allow(azure_client).to receive(:get_storage_account_keys_by_name)
                  .with(targeted_storage_account[:name])
                  .and_return(keys)
              end

              it 'should return the storage account' do
                azure_config.storage_account_name = nil
                expect(Azure::Storage::Client).to receive(:create)
                  .with(
                    storage_account_name: targeted_storage_account[:name],
                    storage_access_key: keys[0],
                    storage_dns_suffix: storage_dns_suffix,
                    user_agent_prefix: 'BOSH-AZURE-CPI'
                  ).and_return(azure_storage_client)
                expect(azure_client).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
                expect(azure_client).to receive(:update_tags_of_storage_account).with(targeted_storage_account[:name], STEMCELL_STORAGE_ACCOUNT_TAGS)

                expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
              end
            end

            context 'When the old storage account is not in the resource group location' do
              let(:targeted_storage_account) do
                {
                  name: 'account1',
                  location: 'another-resource-group-location',
                  sku_name: 'Standard_LRS',
                  sku_tier: 'Standard',
                  storage_blob_host: "https://account1.blob.#{storage_dns_suffix}",
                  storage_table_host: "https://account1.table.#{storage_dns_suffix}"
                }
              end
              let(:storage_accounts) do
                [
                  targeted_storage_account
                ]
              end
              let(:keys) { ['fake-key-1', 'fake-key-2'] }

              before do
                allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
                allow(azure_client).to receive(:get_resource_group)
                  .with(default_resource_group_name)
                  .and_return(resource_group)
                allow(azure_client).to receive(:get_storage_account_by_name)
                  .with(targeted_storage_account[:name])
                  .and_return(targeted_storage_account)
                allow(azure_client).to receive(:get_storage_account_keys_by_name)
                  .with(targeted_storage_account[:name])
                  .and_return(keys)
              end

              it 'should raise an error' do
                azure_config.storage_account_name = nil
                expect(Azure::Storage::Client).to receive(:create)
                  .with(
                    storage_account_name: targeted_storage_account[:name],
                    storage_access_key: keys[0],
                    storage_dns_suffix: storage_dns_suffix,
                    user_agent_prefix: 'BOSH-AZURE-CPI'
                  ).and_return(azure_storage_client)

                expect do
                  storage_account_manager.default_storage_account
                end.to raise_error(/The existing default storage account '#{targeted_storage_account[:name]}' has a different location other than the resource group location./)
              end
            end
          end

          context 'When no standard storage account is found in the resource group' do
            let(:targeted_storage_account) do
              {
                name: 'account1',
                location: resource_group_location,
                sku_name: 'Premium_LRS',
                sku_tier: 'Premium',
                storage_blob_host: "https://account1.blob.#{storage_dns_suffix}",
                storage_table_host: "https://account1.table.#{storage_dns_suffix}"
              }
            end
            let(:storage_accounts) do
              [
                targeted_storage_account
              ]
            end

            before do
              allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(azure_client).to receive(:get_resource_group)
                .with(default_resource_group_name)
                .and_return(resource_group)
              allow(azure_client).to receive(:get_storage_account_by_name)
                .with(targeted_storage_account[:name])
                .and_return(targeted_storage_account)
            end

            it 'should create a new storage account' do
              azure_config.storage_account_name = nil
              expect(azure_client).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
              expect(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
                .with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', 'Storage', resource_group_location, %w[bosh stemcell], true)
                .and_return(targeted_storage_account)

              storage_account_manager.default_storage_account
            end
          end

          context 'When the old storage account with the stemcell table is not found in the resource group' do
            let(:targeted_storage_account) do
              {
                name: 'account1',
                location: resource_group_location,
                sku_name: 'Standard_LRS',
                sku_tier: 'Standard',
                storage_blob_host: "https://account1.blob.#{storage_dns_suffix}",
                storage_table_host: "https://account1.table.#{storage_dns_suffix}"
              }
            end
            let(:storage_accounts) do
              [
                targeted_storage_account
              ]
            end
            let(:keys) { ['fake-key-1', 'fake-key-2'] }

            before do
              allow(azure_client).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(azure_client).to receive(:get_resource_group)
                .with(default_resource_group_name)
                .and_return(resource_group)
              allow(azure_client).to receive(:get_storage_account_by_name)
                .with(targeted_storage_account[:name])
                .and_return(targeted_storage_account)
              allow(azure_client).to receive(:get_storage_account_keys_by_name)
                .with(targeted_storage_account[:name])
                .and_return(keys)
              allow(table_service).to receive(:get_table)
                .and_raise('(404)') # The table stemcells is not found in the storage account
            end

            it 'should create a new storage account' do
              azure_config.storage_account_name = nil
              expect(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
                .with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', 'Storage', resource_group_location, %w[bosh stemcell], true)
                .and_return(targeted_storage_account)

              storage_account_manager.default_storage_account
            end
          end
        end

        context 'When no storage account is found in the resource group location' do
          let(:targeted_storage_account) { { name: 'account1' } }
          before do
            allow(azure_client).to receive(:list_storage_accounts).and_return([])
            allow(azure_client).to receive(:get_resource_group)
              .with(default_resource_group_name)
              .and_return(resource_group)
          end

          it 'should create a new storage account' do
            azure_config.storage_account_name = nil
            expect(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
              .with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', 'Storage', resource_group_location, %w[bosh stemcell], true)
              .and_return(targeted_storage_account)

            storage_account_manager.default_storage_account
          end
        end
      end
    end

    describe '#get_or_create_diagnostics_storage_account' do
      let(:location) { 'fake-location' }
      let(:storage_account) { double('storage-account') }
      let(:diagnostic_tags) do
        {
          'user-agent' => 'bosh',
          'type' => 'bootdiagnostics'
        }
      end
      let(:kind) { 'Storage' }

      it 'should get or create the storage account' do
        expect(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
          .with(diagnostic_tags, 'Standard_LRS', kind, location, [], false)
          .and_return(storage_account)
        expect(
          storage_account_manager.get_or_create_diagnostics_storage_account(location)
        ).to be(storage_account)
      end
    end
  end
end
