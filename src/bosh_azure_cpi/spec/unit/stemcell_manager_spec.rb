# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:table_manager) { instance_double(Bosh::AzureCloud::TableManager) }
  let(:meta_store) { Bosh::AzureCloud::MetaStore.new(table_manager) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:stemcell_manager) { Bosh::AzureCloud::StemcellManager.new(blob_manager, meta_store, storage_account_manager) }

  let(:stemcell_name) { 'fake-stemcell-name' }
  let(:storage_account_name) { 'fake-storage-account-name' }

  before do
    allow(storage_account_manager).to receive(:default_storage_account_name)
      .and_return(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
  end

  describe '#delete_stemcell' do
    context 'the stemcell only exists in default storage account' do
      before do
        allow(table_manager).to receive(:has_table?)
          .and_return(true)
        allow(table_manager).to receive(:query_entities)
          .and_return([])
      end

      it 'deletes the stemcell in default storage account' do
        expect(blob_manager).to receive(:get_blob_properties)
          .and_return({})
        expect(blob_manager).to receive(:delete_blob)

        stemcell_manager.delete_stemcell('foo')
      end
    end

    context 'the stemcell exists in different storage accounts' do
      let(:entities) do
        [
          {
            'PartitionKey' => stemcell_name,
            'RowKey' => storage_account_name,
            'Status' => 'success',
            'Timestamp' => Time.new
          }
        ]
      end
      let(:stemcell_table) { 'stemcells' }
      let(:stemcell_container) { 'stemcell' }

      before do
        allow(table_manager).to receive(:has_table?)
          .and_return(true)
        allow(table_manager).to receive(:query_entities)
          .and_return(entities)
      end

      it 'deletes the stemcell in different storage account' do
        expect(blob_manager).to receive(:get_blob_properties)
          .and_return({}).twice
        expect(blob_manager).to receive(:delete_blob).twice
        allow(table_manager).to receive(:delete_entity)

        stemcell_manager.delete_stemcell(stemcell_name)
      end
    end
  end

  describe '#create_stemcell' do
    before do
      allow(Open3).to receive(:capture2e).and_return(['',
                                                      double('status', exitstatus: 0)])
    end
    it 'creates the stemcell' do
      expect(blob_manager).to receive(:create_page_blob)

      expect(stemcell_manager.create_stemcell('', {})).not_to be_empty
    end
  end

  describe '#has_stemcell?' do
    context 'when the storage account is the default one' do
      it 'handlers stemcell in default storage account' do
        expect(blob_manager).to receive(:get_blob_properties)
          .and_return({})

        expect(
          stemcell_manager.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(true)
      end
    end

    context 'when the storage account is not the default one' do
      let(:storage_account_name) { SecureRandom.uuid }

      before do
        allow(table_manager).to receive(:has_table?)
      end

      context 'when there is an entity record for the stemcell in stemcell_table' do
        context 'when stemcell status is success' do
          let(:entities) do
            [
              {
                'PartitionKey' => stemcell_name,
                'RowKey' => storage_account_name,
                'Status' => 'success'
              }
            ]
          end

          before do
            allow(table_manager).to receive(:query_entities)
              .and_return(entities)
          end

          it 'should return true' do
            expect(blob_manager).not_to receive(:get_blob_properties)

            expect(
              stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
            ).to be(true)
          end
        end

        context 'when stemcell status is unknown' do
          let(:entities) do
            [
              {
                'PartitionKey' => stemcell_name,
                'RowKey' => storage_account_name,
                'Status' => 'unknown'
              }
            ]
          end

          before do
            allow(table_manager).to receive(:query_entities)
              .and_return(entities)
          end

          it 'should raise an error' do
            expect(blob_manager).not_to receive(:get_blob_properties)

            expect do
              stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
            end.to raise_error /The status of the stemcell #{stemcell_name} in the storage account #{storage_account_name} is unknown/
          end
        end

        context 'when stemcell status is pending' do
          context 'when another process copies the stemcell successfully' do
            let(:entities_first_query) do
              [
                {
                  'PartitionKey' => stemcell_name,
                  'RowKey' => storage_account_name,
                  'Status' => 'pending'
                }
              ]
            end
            let(:entities_second_query) do
              [
                {
                  'PartitionKey' => stemcell_name,
                  'RowKey' => storage_account_name,
                  'Status' => 'success'
                }
              ]
            end
            before do
              allow(table_manager).to receive(:query_entities)
                .and_return(entities_first_query, entities_second_query)
            end

            it 'should return true' do
              expect(blob_manager).not_to receive(:get_blob_properties)

              expect(
                stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
              ).to be(true)
            end
          end

          context 'when another process timeouts to copy the stemcell' do
            let(:stemcell_table) { 'stemcells' }
            let(:stemcell_container) { 'stemcell' }
            let(:default_timeout) { 20 * 60 }

            context 'when Timestamp in entities is a String' do
              let(:time_now) { Time.new }
              let(:timestamp_str) { (time_now - (default_timeout - 1)).to_s }
              let(:entities) do
                [
                  {
                    'PartitionKey' => stemcell_name,
                    'RowKey' => storage_account_name,
                    'Status' => 'pending',
                    'Timestamp' => timestamp_str
                  }
                ]
              end
              before do
                allow(Time).to receive(:new).and_return(time_now, (time_now + 1.1))
                allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
              end
              it 'should raise an error' do
                expect(blob_manager).not_to receive(:get_blob_properties)
                # The first query is in get_blob_properties, the second and third queries are in wait_stemcell_copy
                # The third query causes a timeout
                expect(table_manager).to receive(:query_entities)
                  .and_return(entities).exactly(3).times
                expect(table_manager).to receive(:delete_entity)
                  .with(stemcell_table, stemcell_name, storage_account_name)
                expect(blob_manager).to receive(:delete_blob)
                  .with(storage_account_name, stemcell_container, "#{stemcell_name}.vhd")

                expect do
                  stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
                end.to raise_error /The operation of copying the stemcell #{stemcell_name} to the storage account #{storage_account_name} timeouts/
              end
            end

            context 'when Timestamp in entities is a Time object' do
              let(:time_now) { Time.new }
              let(:timestamp) { time_now - (default_timeout - 1) }
              let(:entities) do
                [
                  {
                    'PartitionKey' => stemcell_name,
                    'RowKey' => storage_account_name,
                    'Status' => 'pending',
                    'Timestamp' => timestamp
                  }
                ]
              end

              before do
                allow(Time).to receive(:new).and_return(time_now, (time_now + 1.1))
                allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
              end

              it 'should raise an error' do
                expect(blob_manager).not_to receive(:get_blob_properties)
                # The first query is in get_blob_properties, the second and third queries are in wait_stemcell_copy
                # The third query causes a timeout
                expect(table_manager).to receive(:query_entities)
                  .and_return(entities).exactly(3).times
                expect(table_manager).to receive(:delete_entity)
                  .with(stemcell_table, stemcell_name, storage_account_name)
                expect(blob_manager).to receive(:delete_blob)
                  .with(storage_account_name, stemcell_container, "#{stemcell_name}.vhd")

                expect do
                  stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
                end.to raise_error /The operation of copying the stemcell #{stemcell_name} to the storage account #{storage_account_name} timeouts/
              end
            end
          end
        end
      end

      context 'when there is no entity record for the stemcell in stemcell_table' do
        let(:entity_create) do
          {
            PartitionKey: stemcell_name,
            RowKey: storage_account_name,
            Status: 'pending'
          }
        end
        let(:entity_update) do
          {
            PartitionKey: stemcell_name,
            RowKey: storage_account_name,
            Status: 'success'
          }
        end

        let(:entities_query_before_insert) { [] }
        let(:entities_query_after_insert) do
          [
            {
              'PartitionKey' => stemcell_name,
              'RowKey' => storage_account_name,
              'Status' => 'pending'
            }
          ]
        end

        let(:stemcell_table) { 'stemcells' }
        let(:stemcell_container) { 'stemcell' }
        let(:stemcell_blob_uri) { 'fake-blob-url' }

        it 'should try to copy stecmell, and insert/update record to stemcell table' do
          allow(table_manager).to receive(:insert_entity)
            .with(stemcell_table, entity_create)
            .and_return(true)
          allow(blob_manager).to receive(:get_sas_blob_uri)
            .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
            .and_return(stemcell_blob_uri)
          allow(table_manager).to receive(:query_entities)
            .and_return(entities_query_before_insert, entities_query_after_insert)

          expect(blob_manager).to receive(:copy_blob)
            .with(storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
          expect(table_manager).to receive(:update_entity)
            .with(stemcell_table, entity_update)
          expect(
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          ).to be(true)
        end
      end

      context 'when write to meta store failed' do
        let(:entity_create) do
          {
            PartitionKey: stemcell_name,
            RowKey: storage_account_name,
            Status: 'pending'
          }
        end

        before do
          allow(table_manager).to receive(:query_entities)
            .and_return([])
          allow(table_manager).to receive(:insert_entity)
            .with('stemcells', entity_create)
            .and_raise('insert into table failed.')
        end

        it 'should get one exception' do
          expect do
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          end.to raise_error /insert into table failed./
        end
      end
    end
  end

  describe '#get_stemcell_uri' do
    let(:stemcell_container) { 'stemcell' }
    let(:stemcell_blob_uri) { 'fake-blob-url' }

    before do
      allow(blob_manager).to receive(:get_sas_blob_uri)
        .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
        .and_return(stemcell_blob_uri)
    end

    it 'gets the uri of the stemcell' do
      expect(
        stemcell_manager.get_stemcell_uri(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
      ).to eq(stemcell_blob_uri)
    end
  end

  describe '#get_stemcell_info' do
    let(:stemcell_container) { 'stemcell' }
    let(:stemcell_blob_uri) { 'fake-blob-url' }

    before do
      allow(blob_manager).to receive(:get_blob_uri)
        .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
        .and_return(stemcell_blob_uri)
    end

    context 'when metadata is nil' do
      let(:stemcell_blob_metadata) { nil }

      before do
        allow(blob_manager).to receive(:get_blob_metadata)
          .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
          .and_return(stemcell_blob_metadata)
      end

      it 'should throw an error' do
        expect do
          stemcell_manager.get_stemcell_info(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        end.to raise_error /The stemcell '#{stemcell_name}' does not exist in the storage account '#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}'/
      end
    end

    context 'when metadata is not nil' do
      let(:stemcell_blob_metadata) { { 'foo' => 'bar' } }

      before do
        allow(blob_manager).to receive(:get_blob_metadata)
          .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
          .and_return(stemcell_blob_metadata)
      end

      it 'should throw an error' do
        stemcell_info = stemcell_manager.get_stemcell_info(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        expect(stemcell_info.uri).to eq(stemcell_blob_uri)
        expect(stemcell_info.metadata).to eq(stemcell_blob_metadata)
      end
    end
  end
end
