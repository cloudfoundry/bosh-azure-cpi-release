require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager2 do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:table_manager) { instance_double(Bosh::AzureCloud::TableManager) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:stemcell_manager2) { Bosh::AzureCloud::StemcellManager2.new(blob_manager, table_manager, storage_account_manager, client2) }
  let(:stemcell_name) { "fake-stemcell-name" }

  before do
    allow(storage_account_manager).to receive(:default_storage_account_name).
      and_return(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
  end

  describe "#delete_stemcell" do
    let(:user_images) {
      [
        { :name => "#{stemcell_name}-postfix1" },
        { :name => "#{stemcell_name}-postfix2" },
        { :name => "prefix-#{stemcell_name}" },
        { :name => "prefix-#{stemcell_name}-postfix" }
      ]
    }

    let(:storage_accounts) {
      [
        { :name => "foo" },
        { :name => "bar" }
      ]
    }

    let(:entities) {
      [
        {
          'PartitionKey' => stemcell_name,
          'RowKey'       => 'fake-storage-account-name',
          'Status'       => 'success',
          'Timestamp'    => Time.now
        }
      ]
    }

    before do
      allow(client2).to receive(:list_user_images).
        and_return(user_images)
      allow(client2).to receive(:list_storage_accounts).
        and_return(storage_accounts)
      allow(table_manager).to receive(:has_table?).
        and_return(true)
      allow(blob_manager).to receive(:get_blob_properties).
        and_return({"foo" => "bar"}) # The blob properties are not nil, which means the stemcell exists
      allow(table_manager).to receive(:query_entities).
        and_return(entities)
    end

    it "deletes the stemcell in default storage account" do
      # Delete the user images whose prefix is the stemcell_name
      expect(client2).to receive(:delete_user_image).
        with("#{stemcell_name}-postfix1").once
      expect(client2).to receive(:delete_user_image).
        with("#{stemcell_name}-postfix2").once

      # Delete all stemcells with the given stemcell name in all storage accounts
      expect(blob_manager).to receive(:delete_blob).twice

      # Delete all records whose PartitionKey is the given stemcell name
      allow(table_manager).to receive(:delete_entity)

      stemcell_manager2.delete_stemcell(stemcell_name)
    end
  end  

  describe "#has_stemcell?" do
    context "when the storage account has the stemcell" do
      it "should return true" do
        expect(blob_manager).to receive(:get_blob_properties).
          and_return({})

        expect(
          stemcell_manager2.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(true)
      end
    end

    context "when the storage account doesn't have the stemcell" do
      it "should return false" do
        expect(blob_manager).to receive(:get_blob_properties).
          and_return(nil)

        expect(
          stemcell_manager2.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(false)
      end
    end
  end

  describe "#get_user_image_info" do
    let(:storage_account_type) { "Standard_LRS" }
    let(:location) { "SoutheastAsia" }
    let(:user_image_name) { "#{stemcell_name}-#{storage_account_type}-#{location}" }
    let(:user_image_id) { "fake-user-image-id" }
    let(:tags) {
      {
        "foo" => "bar"
      }
    }
    let(:user_image) {
      {
        :id => user_image_id,
        :tags => tags
      }
    }

    context "when the user image already exists" do
      before do
        allow(client2).to receive(:get_user_image_by_name).
          with(user_image_name).
          and_return(user_image)
      end

      it "should return the user image information" do
        stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
        expect(stemcell_info.uri).to eq(user_image_id)
        expect(stemcell_info.metadata).to eq(tags)
      end
    end

    context "when the user image doesn't exist" do
      before do
        allow(client2).to receive(:get_user_image_by_name).
          with(user_image_name).
          and_return(nil)
      end

      context "when the stemcell doesn't exist in the default storage account" do
        let(:default_storage_account) {
          {
            :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
          }
        }

        before do
          allow(storage_account_manager).to receive(:default_storage_account).
            and_return(default_storage_account)
          allow(blob_manager).to receive(:get_blob_properties).
            and_return(nil) # The blob properties are nil, which means the stemcell doesn't exist
        end

        it "should raise an error" do
          expect{
            stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
          }.to raise_error /Failed to get user image for the stemcell `#{stemcell_name}'/
        end
      end

      context "when the stemcell exists in the default storage account" do
        before do
          allow(blob_manager).to receive(:get_blob_properties).
            and_return({"foo" => "bar"}) # The blob properties are not nil, which means the stemcell exists
        end

        let(:stemcell_container) { 'stemcell' }
        let(:stemcell_blob_uri) { 'fake-blob-url' }
        let(:stemcell_blob_metadata) { { "foo" => "bar" } }

        before do
          allow(blob_manager).to receive(:get_blob_uri).
            with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
            and_return(stemcell_blob_uri)
          allow(blob_manager).to receive(:get_blob_metadata).
            with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
            and_return(stemcell_blob_metadata)
          allow(client2).to receive(:create_user_image)
          allow(client2).to receive(:get_user_image_by_name).
            with(user_image_name).
            and_return(user_image)
        end

        context "when the location of the default storage account is the targeted location" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => "SoutheastAsia"
            }
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
          end


          it "should get the stemcell from the default storage account, create a new user image and return the user image information" do
            stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
            expect(stemcell_info.uri).to eq(user_image_id)
            expect(stemcell_info.metadata).to eq(tags)
          end
        end

        context "when the location of the default storage account is not the targeted location" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => "SoutheastAsia-different"
            }
          }
          let(:storage_accounts) {
            [
              {
                :name => "foo",
                :location => "SoutheastAsia",
                :tags => {
                  "user-agent" => "bosh",
                  "type" => "stemcell"
                }
              }
            ]
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
            allow(client2).to receive(:list_storage_accounts).
              and_return(storage_accounts)
          end

          it "should get the stemcell from another storage account, create a new user image and return the user image information" do
            # TODO: Mock the file mutex

            stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
            expect(stemcell_info.uri).to eq(user_image_id)
            expect(stemcell_info.metadata).to eq(tags)
          end
        end
      end
    end
  end
end
