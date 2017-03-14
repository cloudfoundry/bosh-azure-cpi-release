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
        expect(storage_account_manager).not_to receive(:default_storage_account)
        stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
        expect(stemcell_info.uri).to eq(user_image_id)
        expect(stemcell_info.metadata).to eq(tags)
      end
    end

    context "when the user image doesn't exist" do
      context "when the stemcell doesn't exist in the default storage account" do
        let(:default_storage_account) {
          {
            :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
          }
        }

        before do
          allow(client2).to receive(:get_user_image_by_name).
            with(user_image_name).
            and_return(nil)
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
        let(:stemcell_container) { 'stemcell' }
        let(:stemcell_blob_uri) { 'fake-blob-url' }
        let(:stemcell_blob_metadata) { { "foo" => "bar" } }
        let(:user_image) {
          {
            :id => user_image_id,
            :tags => tags,
            :provisioning_state => "Succeeded"
          }
        }

        before do
          allow(client2).to receive(:get_user_image_by_name).
            with(user_image_name).
            and_return(nil, user_image) # The first return value nil means the user image doesn't exist, the second one user_image is returned after the image is created.
          allow(blob_manager).to receive(:get_blob_properties).
            with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
            and_return({"foo" => "bar"}) # The stemcell exists in the default storage account
          allow(client2).to receive(:create_user_image)
        end

        context "when the location of the default storage account is the targeted location" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => location
            }
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
            allow(blob_manager).to receive(:get_blob_uri).
              with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
              and_return(stemcell_blob_uri)
            allow(blob_manager).to receive(:get_blob_metadata).
              with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
              and_return(stemcell_blob_metadata)
          end

          it "should get the stemcell from the default storage account, create a new user image and return the user image information" do
            expect(client2).not_to receive(:list_storage_accounts)
            stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
            expect(stemcell_info.uri).to eq(user_image_id)
            expect(stemcell_info.metadata).to eq(tags)
          end
        end

        context "when the location of the default storage account is not the targeted location" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => "#{location}-different"
            }
          }

          before do
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
          end

          context "when the storage account with tags exists in the specified location" do
            let(:existing_storage_account_name) { "existing-storage-account-name-other-than-default-storage-account" }
            let(:storage_accounts) {
              [
                {
                  :name => existing_storage_account_name,
                  :location => location,
                  :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
                }
              ]
            }
            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              # The following two allows are for get_stemcell_info of stemcell_manager.rb
              allow(blob_manager).to receive(:get_blob_uri).
                with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_uri)
              allow(blob_manager).to receive(:get_blob_metadata).
                with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_metadata)
            end

            context "when the stemcell exists in the exising storage account" do
              before do
                allow(blob_manager).to receive(:get_blob_properties).
                  with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                  and_return({"foo"=>"bar"}) # The stemcell exists in the existing storage account
              end

              it "should create a new user image and return the user image information" do
                expect(blob_manager).not_to receive(:get_blob_uri).
                  with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
                expect(blob_manager).not_to receive(:copy_blob)
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end

            context "when the stemcell doesn't exist in the exising storage account" do
              before do
                allow(blob_manager).to receive(:get_blob_properties).
                  with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                  and_return(nil) # The stemcell doesn't exist in the existing storage account
              end

              after do
                File.delete('/tmp/bosh-lock-copy-stemcell') if File.exists?('/tmp/bosh-lock-copy-stemcell')
              end

              it "should copy the stemcell from default storage account to an existing storage account, create a new user image and return the user image information" do
                expect(blob_manager).to receive(:get_blob_uri).
                  with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
                  and_return(stemcell_blob_uri)
                expect(blob_manager).to receive(:copy_blob).
                  with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end
          end

          context "when the storage account with doesn't exist in the specified location" do
            let(:new_storage_account_name) { "new-storage-account-name" }
            let(:storage_accounts) {
              [
                {
                  :name => new_storage_account_name,
                  :location => location,
                  :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
                }
              ]
            }
            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              # The following two allows are for get_stemcell_info of stemcell_manager.rb
              allow(blob_manager).to receive(:get_blob_uri).
                with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_uri)
              allow(blob_manager).to receive(:get_blob_metadata).
                with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_metadata)
              allow(blob_manager).to receive(:get_blob_properties).
                with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(nil) # The stemcell doesn't exist in the new storage account
            end

            after do
              File.delete('/tmp/bosh-lock-copy-stemcell') if File.exists?('/tmp/bosh-lock-copy-stemcell')
            end

            it "should copy the stemcell from default storage account to the new storage account, create a new user image and return the user image information" do
              expect(blob_manager).to receive(:get_blob_uri).
                with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_uri)
              expect(blob_manager).to receive(:copy_blob).
                with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
              stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              expect(stemcell_info.uri).to eq(user_image_id)
              expect(stemcell_info.metadata).to eq(tags)
            end
          end
        end

        context "Check whether user image is created" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => location
            }
          }
          before do
            allow(client2).to receive(:create_user_image)
            allow(storage_account_manager).to receive(:default_storage_account).
              and_return(default_storage_account)
            allow(blob_manager).to receive(:get_blob_properties).
              with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
              and_return({"foo" => "bar"}) # The stemcell exists in the default storage account
            allow(blob_manager).to receive(:get_blob_uri).
              with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
              and_return(stemcell_blob_uri)
            allow(blob_manager).to receive(:get_blob_metadata).
              with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
              and_return(stemcell_blob_metadata)
          end

          context "when user image can't be found" do
            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil, nil) # The first return value nil means the user image doesn't exist, the others are returned after the image is created.
            end

            it "should raise an error" do
              expect {
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              }.to raise_error(/get_user_image: Can not find a user image with the name `#{user_image_name}'/)
            end
          end

          context "when the provisioning state of user image is Succeeded finally" do
            let(:user_image_in_progress) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "InProgress"
              }
            }
            let(:user_image_succeeded) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "Succeeded"
              }
            }

            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil, user_image_in_progress, user_image_in_progress, user_image_succeeded) # The first return value nil means the user image doesn't exist, the others are returned after the image is created.
            end

            it "should create a new user image and check the provisionging state" do
              stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              expect(stemcell_info.uri).to eq(user_image_id)
              expect(stemcell_info.metadata).to eq(tags)
            end
          end

          context "when the provisioning state of user image is Failed finally" do
            let(:user_image_in_progress) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "InProgress"
              }
            }
            let(:user_image_failed) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "Failed"
              }
            }

            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil, user_image_in_progress, user_image_in_progress, user_image_failed) # The first return value nil means the user image doesn't exist, the others are returned after the image is created.
            end

            it "should raise an error" do
              expect {
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              }.to raise_error(/get_user_image: Failed to create a user image `#{user_image_name}' whose provisioning state is `Failed'/)
            end
          end

          context "when the provisioning state of user image is Canceled finally" do
            let(:user_image_in_progress) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "InProgress"
              }
            }
            let(:user_image_canceled) {
              {
                :id => user_image_id,
                :tags => tags,
                :provisioning_state => "Canceled"
              }
            }

            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil, user_image_in_progress, user_image_in_progress, user_image_canceled) # The first return value nil means the user image doesn't exist, the others are returned after the image is created.
            end

            it "should raise an error" do
              expect {
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              }.to raise_error(/get_user_image: Failed to create a user image `#{user_image_name}' whose provisioning state is `Canceled'/)
            end
          end
        end
      end
    end
  end
end
