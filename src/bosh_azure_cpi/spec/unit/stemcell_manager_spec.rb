require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:table_manager) { instance_double(Bosh::AzureCloud::TableManager) }
  let(:stemcell_manager) { Bosh::AzureCloud::StemcellManager.new(azure_properties, blob_manager, table_manager) }

  let(:stemcell_name) { "fake-stemcell-name" }
  let(:storage_account_name) { "fake-storage-account-name" }

  describe "#prepare" do
    context "when the container exists" do
      before do
        allow(blob_manager).to receive(:has_container?).
          and_return(true)
      end

      it "should not create the container" do
        expect(blob_manager).not_to receive(:create_container)

        expect {
          stemcell_manager.prepare(storage_account_name)
        }.not_to raise_error
      end
    end

    context "when the container does not exist" do
      before do
        allow(blob_manager).to receive(:has_container?).
          and_return(false)
      end

      it "should create the container" do
        expect(blob_manager).to receive(:create_container).
          and_return(true)

        expect {
          stemcell_manager.prepare(storage_account_name)
        }.not_to raise_error
      end
    end
  end

  describe "#create_stemcell" do
    before do
      allow(Open3).to receive(:capture2e).and_return(["",
        double("status", :exitstatus => 0)])
    end
    it "creates the stemcell" do
      expect(blob_manager).to receive(:create_page_blob)

      expect(stemcell_manager.create_stemcell("",{})).not_to be_empty
    end
  end  

  describe "#delete_stemcell" do
    context "the stemcell only exists in default storage account" do
      before do
        allow(table_manager).to receive(:has_table?).
          and_return(true)
        allow(table_manager).to receive(:query_entities).
          and_return([])
      end

      it "deletes the stemcell in default storage account" do
        expect(blob_manager).to receive(:get_blob_properties).
          and_return({})
        expect(blob_manager).to receive(:delete_blob)

        stemcell_manager.delete_stemcell("foo")
      end
    end

    context "the stemcell exists in different storage accounts" do
      let(:entities) {
        [
          {
            'PartitionKey' => stemcell_name,
            'RowKey'       => storage_account_name,
            'Status'       => 'success',
            'Timestamp'    => Time.now
          }
        ]
      }
      let(:stemcell_table) { 'stemcells' }
      let(:stemcell_container) { 'stemcell' }

      before do
        allow(table_manager).to receive(:has_table?).
          and_return(true)
        allow(table_manager).to receive(:query_entities).
          and_return(entities)
      end

      it "deletes the stemcell in different storage account" do
        expect(blob_manager).to receive(:get_blob_properties).
          and_return({}).twice
        expect(blob_manager).to receive(:delete_blob).twice
        allow(table_manager).to receive(:delete_entity)

        stemcell_manager.delete_stemcell(stemcell_name)
      end
    end
  end  

  describe "#has_stemcell?" do
    context "when the storage account is the default one" do
      it "handlers stemcell in default storage account" do
        expect(blob_manager).to receive(:get_blob_properties).
          and_return({})

        expect(
          stemcell_manager.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(true)
      end
    end

    context "when the storage account is not the default one" do
      let(:storage_account_name) { "different-storage-account" }

      before do
        allow(table_manager).to receive(:has_table?)
      end

      context "when stemcell status is success" do
        let(:entities) {
          [
            {
              'PartitionKey' => stemcell_name,
              'RowKey'       => storage_account_name,
              'Status'       => 'success'
            }
          ]
        }

        before do
          allow(table_manager).to receive(:query_entities).
            and_return(entities)
        end

        it "handlers stemcell in different storage account" do
          expect(blob_manager).not_to receive(:get_blob_properties)

          expect(
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          ).to be(true)
        end
      end

      context "when stemcell status is success" do
        let(:entities) {
          [
            {
              'PartitionKey' => stemcell_name,
              'RowKey'       => storage_account_name,
              'Status'       => 'success'
            }
          ]
        }

        before do
          allow(table_manager).to receive(:query_entities).
            and_return(entities)
        end

        it "should return true" do
          expect(blob_manager).not_to receive(:get_blob_properties)

          expect(
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          ).to be(true)
        end
      end

      context "when stemcell status is unknown" do
        let(:entities) {
          [
            {
              'PartitionKey' => stemcell_name,
              'RowKey'       => storage_account_name,
              'Status'       => 'unknown'
            }
          ]
        }

        before do
          allow(table_manager).to receive(:query_entities).
            and_return(entities)
        end

        it "should raise an error" do
          expect(blob_manager).not_to receive(:get_blob_properties)

          expect{
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          }.to raise_error /The status of the stemcell #{stemcell_name} in the storage account #{storage_account_name} is unknown/
        end
      end

      context "when stemcell status is pending and it timeouts" do
        let(:entities) {
          [
            {
              'PartitionKey' => stemcell_name,
              'RowKey'       => storage_account_name,
              'Status'       => 'pending',
              'Timestamp'    => Time.now - 19 * 60
            }
          ]
        }
        let(:stemcell_table) { 'stemcells' }
        let(:stemcell_container) { 'stemcell' }

        before do
          allow(table_manager).to receive(:query_entities).
            and_return(entities)
        end

        it "should raise an error" do
          expect(blob_manager).not_to receive(:get_blob_properties)
          expect(table_manager).to receive(:delete_entity).
            with(stemcell_table, stemcell_name, storage_account_name)
          expect(blob_manager).to receive(:delete_blob).
            with(storage_account_name, stemcell_container, "#{stemcell_name}.vhd")

          expect{
            stemcell_manager.has_stemcell?(storage_account_name, stemcell_name)
          }.to raise_error
        end
      end
    end
  end
end
