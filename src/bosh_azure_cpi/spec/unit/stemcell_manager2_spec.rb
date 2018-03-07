require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager2 do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:table_manager) { instance_double(Bosh::AzureCloud::TableManager) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:stemcell_manager2) { Bosh::AzureCloud::StemcellManager2.new(blob_manager, table_manager, storage_account_manager, client2) }

  before do
    allow(storage_account_manager).to receive(:default_storage_account_name).
      and_return(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
  end

  let(:stemcell_uuid) { "fbb636e9-89b6-432b-b52c-b5cd93654900" }
  let(:stemcell_name) { "bosh-stemcell-#{stemcell_uuid}" }

  describe "#delete_stemcell" do
    let(:user_images) {
      [
        { :name => "#{stemcell_uuid}-postfix" }, # New format
        { :name => "#{stemcell_name}-postfix" },  # Old format
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
      # Delete the user images whose prefix is the stemcell_uuid or stemcell_name
      expect(client2).to receive(:delete_user_image).
        with("#{stemcell_uuid}-postfix").once
      expect(client2).to receive(:delete_user_image).
        with("#{stemcell_name}-postfix").once

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
    let(:user_image_name_deprecated) { "#{stemcell_name}-#{storage_account_type}-#{location}" }
    let(:user_image_name) { "#{stemcell_uuid}-S-#{location}" }
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

    # CPI will try to delete the user image with the old format name no matter it exists
    before do
      allow(client2).to receive(:delete_user_image).with(user_image_name_deprecated)
    end

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

          let(:lock_creating_user_image) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
          before do
            allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_creating_user_image)
            allow(lock_creating_user_image).to receive(:lock).and_return(true)
            allow(lock_creating_user_image).to receive(:unlock)
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
            let(:storage_account) {
              {
                :name => existing_storage_account_name,
                :location => location,
                :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
              }
            }
            let(:lock_copy_blob) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }

            before do
              allow(storage_account_manager).to receive(:find_storage_account_by_tags).
                with(STEMCELL_STORAGE_ACCOUNT_TAGS, location).
                and_return(storage_account)
              # The following two allows are for get_stemcell_info of stemcell_manager.rb
              allow(blob_manager).to receive(:get_blob_uri).
                with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_uri)
              allow(blob_manager).to receive(:get_blob_metadata).
                with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                and_return(stemcell_blob_metadata)
              allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_copy_blob)
            end

            context "when the lock of copying blob is not acquired" do
              before do
                allow(lock_copy_blob).to receive(:lock).and_return(false)
                allow(lock_copy_blob).to receive(:expired).and_return("fake-expired-value")
              end

              context "when copying blob timeouts" do
                before do
                  allow(lock_copy_blob).to receive(:wait).and_raise(Bosh::AzureCloud::Helpers::LockTimeoutError)
                end

                it "should raise a timeout error" do
                  expect(blob_manager).not_to receive(:get_blob_uri)
                  expect(blob_manager).not_to receive(:copy_blob)
                  expect(File).to receive(:open).with(Bosh::AzureCloud::Helpers::CPI_LOCK_DELETE, "wb")
                  expect {
                    stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  }.to raise_error /get_user_image: Failed to finish the copying process of the stemcell/
                end
              end

              context "when copying blob finishes before it timeouts" do
                before do
                  allow(lock_copy_blob).to receive(:wait)
                end

                it "should create a new user image and return the user image information" do
                  expect(blob_manager).not_to receive(:copy_blob)
                  stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  expect(stemcell_info.uri).to eq(user_image_id)
                  expect(stemcell_info.metadata).to eq(tags)
                end
              end
            end

            context "when the lock of copying blob is acquired" do
              before do
                allow(lock_copy_blob).to receive(:lock).and_return(true)
              end

              context "when the stemcell exists in the exising storage account" do
                before do
                  allow(blob_manager).to receive(:get_blob_properties).
                    with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd").
                    and_return({"foo"=>"bar"}) # The stemcell exists in the existing storage account
                  allow(lock_copy_blob).to receive(:unlock)
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

                context "when copying blob is successful" do
                  before do
                    allow(lock_copy_blob).to receive(:update)
                    allow(lock_copy_blob).to receive(:unlock)
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

                context "when copying blob raises an error" do
                  before do
                    allow(blob_manager).to receive(:get_blob_uri).
                      with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
                      and_return(stemcell_blob_uri)
                    expect(blob_manager).to receive(:copy_blob).
                      with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri).
                      and_raise("Error when copying blobs")
                  end

                  it "should raise an error" do
                    expect(lock_copy_blob).not_to receive(:unlock)
                    expect(File).to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
                    expect {
                      stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                    }.to raise_error /get_user_image: Failed to finish the copying process of the stemcell `#{stemcell_name}'/
                  end
                end
              end
            end
          end

          context "when the storage account with tags doesn't exist in the specified location" do
            context "when it fails to create the new storage account" do
              context "when an error is thrown when creating the new storage account" do
                before do
                  allow(storage_account_manager).to receive(:find_storage_account_by_tags).and_return(nil)
                  allow(storage_account_manager).to receive(:create_storage_account_by_tags).
                    and_raise("Error when creating storage account")
                end

                it "raise an error" do
                  expect {
                    stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  }.to raise_error /Error when creating storage account/
                end
              end
            end

            context "when it creates the new storage account successfully, and copies the stemcell from default storage account to the new storage account" do
              let(:new_storage_account_name) { "54657da5936725e199fd616e" }
              let(:storage_account) {
                {
                  :name => new_storage_account_name,
                  :location => location,
                  :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
                }
              }
              let(:lock_copy_blob) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }

              before do
                allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_copy_blob)

                # check storage account
                allow(storage_account_manager).to receive(:find_storage_account_by_tags).and_return(nil)

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

                # Copy blob
                allow(lock_copy_blob).to receive(:lock).and_return(true)
                allow(lock_copy_blob).to receive(:unlock)
                allow(blob_manager).to receive(:get_blob_uri).
                  with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
                  and_return(stemcell_blob_uri)
                allow(blob_manager).to receive(:copy_blob).
                  with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
              end

              it "should create a new user image and return the user image information" do
                expect(storage_account_manager).to receive(:create_storage_account_by_tags).
                  with(STEMCELL_STORAGE_ACCOUNT_TAGS, storage_account_type, location, ['stemcell'], false).
                  and_return(storage_account)
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end
          end
        end

        context "When CPI is going to create user image" do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :location => location
            }
          }
          before do
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

          let(:lock_creating_user_image) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
          before do
            allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_creating_user_image)
          end

          context "when the lock of creating the user image timeouts" do
            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil)
              allow(lock_creating_user_image).to receive(:lock).and_return(false)
              allow(lock_creating_user_image).to receive(:wait).and_raise(Bosh::AzureCloud::Helpers::LockTimeoutError)
              allow(lock_creating_user_image).to receive(:expired).and_return(60)
            end

            it "should mark deleting locks and raise an error" do
              expect(lock_creating_user_image).not_to receive(:unlock)
              expect(File).to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
              expect {
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              }.to raise_error(/get_user_image: Failed to create the user image `#{user_image_name}'/)
            end
          end

          context "when the lock of creating the user image fails due to other errors" do
            before do
              allow(client2).to receive(:get_user_image_by_name).
                with(user_image_name).
                and_return(nil)
              allow(lock_creating_user_image).to receive(:lock).and_raise(Bosh::AzureCloud::Helpers::LockError)
            end

            it "should mark deleting locks and raise an error" do
              expect(lock_creating_user_image).not_to receive(:unlock)
              expect(File).to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
              expect {
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              }.to raise_error(/get_user_image: Failed to create the user image `#{user_image_name}'/)
            end
          end

          context "when creating user image is locked" do
            before do
              allow(lock_creating_user_image).to receive(:lock).and_return(true)
              allow(lock_creating_user_image).to receive(:unlock)
            end

            context "when user image can't be found" do
              before do
                allow(client2).to receive(:get_user_image_by_name).
                  with(user_image_name).
                  and_return(nil, nil) # The first return value nil means the user image doesn't exist, the second nil means that the user image can't be found after creation.
              end

              it "should raise an error" do
                expect(File).not_to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
                expect {
                  stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                }.to raise_error(/get_user_image: Can not find a user image with the name `#{user_image_name}'/)
              end
            end

            context "when the user image is created successfully" do
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
                  and_return(user_image)
              end

              it "should return the new user image" do
                expect(File).not_to receive(:open).with("/tmp/azure_cpi/DELETING-LOCKS", "wb")
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end
          end
        end
      end
    end
  end
end
