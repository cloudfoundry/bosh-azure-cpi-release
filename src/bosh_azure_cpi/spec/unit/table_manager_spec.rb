# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::TableManager do
  let(:azure_config) { mock_azure_config }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:table_manager) { Bosh::AzureCloud::TableManager.new(azure_config, storage_account_manager, azure_client) }

  let(:table_name) { 'fake-table-name' }
  let(:keys) { ['fake-key-1', 'fake-key-2'] }

  let(:azure_storage_client) { instance_double(Azure::Storage::Client) }
  let(:table_service) { instance_double(Azure::Storage::Table::TableService) }
  let(:exponential_retry) { instance_double(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter) }
  let(:storage_dns_suffix) { 'fake-storage-dns-suffix' }
  let(:blob_host) { "https://#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}.blob.#{storage_dns_suffix}" }
  let(:table_host) { "https://#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}.table.#{storage_dns_suffix}" }
  let(:storage_account) do
    {
      id: 'foo',
      name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
      location: 'bar',
      provisioning_state: 'bar',
      account_type: 'foo',
      storage_blob_host: blob_host,
      storage_table_host: table_host
    }
  end
  let(:request_id) { 'fake-client-request-id' }
  let(:options) do
    {
      request_id: request_id
    }
  end

  before do
    allow(storage_account_manager).to receive(:default_storage_account)
      .and_return(storage_account)
    allow(Azure::Storage::Client).to receive(:create)
      .and_return(azure_storage_client)
    allow(Bosh::AzureCloud::AzureClient).to receive(:new)
      .and_return(azure_client)
    allow(azure_client).to receive(:get_storage_account_keys_by_name)
      .and_return(keys)
    allow(azure_client).to receive(:get_storage_account_by_name)
      .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
      .and_return(storage_account)

    allow(azure_storage_client).to receive(:table_client)
      .and_return(table_service)
    allow(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter).to receive(:new)
      .and_return(exponential_retry)
    allow(table_service).to receive(:with_filter).with(exponential_retry)

    allow(SecureRandom).to receive(:uuid).and_return(request_id)
  end

  class MyArray < Array
    attr_accessor :continuation_token
  end

  class MyEntity
    def initialize
      @properties = {}
      yield self if block_given?
    end
    attr_accessor :properties
  end

  describe '#has_table?' do
    context 'when the table exists' do
      before do
        allow(table_service).to receive(:get_table)
          .with(table_name, options)
      end

      it 'should return true' do
        expect(table_manager.has_table?(table_name)).to be(true)
      end
    end

    context 'when the table does not exist' do
      before do
        allow(table_service).to receive(:get_table)
          .and_raise('(404)')
      end

      it 'returns false' do
        expect(table_manager.has_table?(table_name)).to be(false)
      end
    end

    context 'when the status code is not 404' do
      before do
        allow(table_service).to receive(:get_table)
          .and_raise('Not-404-Error')
      end

      it 'should raise an error' do
        expect do
          table_manager.has_table?(table_name)
        end.to raise_error /Not-404-Error/
      end
    end
  end

  describe '#query_entities' do
    records_with_token = MyArray.new
    entity1 = MyEntity.new do |e|
      e.properties = 'foo'
    end
    records_with_token.push(entity1)
    fake_continuation_token = {
      next_partition_key: 'p_key',
      next_row_key: 'r_key'
    }
    records_with_token.continuation_token = fake_continuation_token

    records_without_token = MyArray.new
    entity2 = MyEntity.new do |e|
      e.properties = 'bar'
    end
    records_without_token.push(entity2)
    records_without_token.continuation_token = nil

    before do
      allow(table_service).to receive(:query_entities)
        .with(table_name, options)
        .and_return(records_with_token)
      allow(table_service).to receive(:query_entities)
        .with(table_name, continuation_token: fake_continuation_token, request_id: request_id)
        .and_return(records_without_token)
    end

    it 'returns the entities' do
      expect(
        table_manager.query_entities(table_name, {})
      ).to eq(%w[foo bar])
    end
  end

  describe '#insert_entity' do
    entity = MyEntity.new do |e|
      e.properties = 'foo'
    end

    context 'when the specified entity does not exist' do
      before do
        allow(table_service).to receive(:insert_entity)
          .with(table_name, entity, options)
      end

      it 'should return true' do
        expect(table_manager.insert_entity(table_name, entity)).to be(true)
      end
    end

    context 'when the specified entity already exists' do
      before do
        allow(table_service).to receive(:insert_entity)
          .and_raise('(409)')
      end

      it 'should return false' do
        expect(table_manager.insert_entity(table_name, entity)).to be(false)
      end
    end

    context 'when the status code is not 409' do
      before do
        allow(table_service).to receive(:insert_entity)
          .and_raise('Not-409-Error')
      end

      it 'should raise an error' do
        expect do
          table_manager.insert_entity(table_name, entity)
        end.to raise_error /Not-409-Error/
      end
    end
  end

  describe '#delete_entity' do
    let(:partition_key) { 'p_key' }
    let(:row_key) { 'r_key' }

    context 'when the specified entity exists' do
      before do
        allow(table_service).to receive(:delete_entity)
          .with(table_name, partition_key, row_key, options)
      end

      it 'should not raise an error' do
        expect do
          table_manager.delete_entity(table_name, partition_key, row_key)
        end.not_to raise_error
      end
    end

    context 'when the specified entity does not exist' do
      before do
        allow(table_service).to receive(:delete_entity)
          .and_raise('(404)')
      end

      it 'should not raise an error' do
        expect do
          table_manager.delete_entity(table_name, partition_key, row_key)
        end.not_to raise_error
      end
    end

    context 'when the status code is not 404' do
      before do
        allow(table_service).to receive(:delete_entity)
          .and_raise('Not-404-Error')
      end

      it 'should raise an error' do
        expect do
          table_manager.delete_entity(table_name, partition_key, row_key)
        end.to raise_error /Not-404-Error/
      end
    end
  end

  describe '#update_entity' do
    entity = MyEntity.new do |e|
      e.properties = 'foo'
    end

    before do
      allow(table_service).to receive(:update_entity)
        .with(table_name, entity, options)
    end

    it 'does not raise an error' do
      expect do
        table_manager.update_entity(table_name, entity)
      end.not_to raise_error
    end
  end
end
