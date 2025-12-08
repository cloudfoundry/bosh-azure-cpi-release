# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::StemcellManager2 do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:table_manager) { instance_double(Bosh::AzureCloud::TableManager) }
  let(:meta_store) { Bosh::AzureCloud::MetaStore.new(table_manager) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:azure_config) { Bosh::AzureCloud::AzureConfig.new({}) }
  let(:stemcell_manager2) { Bosh::AzureCloud::StemcellManager2.new(azure_config, blob_manager, meta_store, storage_account_manager, azure_client) }

  before do
    allow(storage_account_manager).to receive(:default_storage_account_name)
      .and_return(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)

    allow(storage_account_manager).to receive(:use_default_account_for_cleaning)
      .and_return(false)
  end

  let(:stemcell_uuid) { 'fbb636e9-89b6-432b-b52c-b5cd93654900' }
  let(:stemcell_name) { "bosh-stemcell-#{stemcell_uuid}" }

  describe '#create_stemcell' do
    before do
      allow(Open3).to receive(:capture2e).and_return(['',
                                                      double('status', exitstatus: 0)])
      allow(azure_client).to receive(:create_gallery_image_definition)
      allow(azure_client).to receive(:create_update_gallery_image_version)
    end

    context 'when compute gallery is disabled' do
      it 'does not create gallery images' do
        expect(blob_manager).to receive(:create_page_blob)

        stemcell_manager2.create_stemcell('fake-image-path', { 'version' => '1.2' })

        expect(azure_client).not_to have_received(:create_gallery_image_definition)
        expect(azure_client).not_to have_received(:create_update_gallery_image_version)
      end
    end

    context 'when compute gallery is enabled' do
      let(:azure_config) do
        Bosh::AzureCloud::AzureConfig.new(
          'compute_gallery_name' => 'fake-gallery',
          'location' => 'fake-location'
        )
      end
      let(:stemcell_properties) do
        {
          'version' => '1.2',
          'os_type' => 'linux',
          'infrastructure' => 'azure',
          'disk' => 30720,
          'name' => 'bosh-azure-hyperv-ubuntu-trusty-go_agent'
        }
      end
      let(:blob_uri) { 'fake-blob-uri' }

      before do
        allow(blob_manager).to receive(:create_page_blob)
        allow(blob_manager).to receive(:get_blob_uri).and_return(blob_uri)
        allow(SecureRandom).to receive(:uuid).and_return(stemcell_uuid)
        allow(azure_client).to receive(:get_gallery_image_definition).and_return(nil)
        allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_raise('Not found')
        allow(azure_client).to receive(:get_gallery_image_version).and_return(nil)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:open).and_yield(StringIO.new('fake-image-content'))
        allow_any_instance_of(Digest::SHA256).to receive(:hexdigest).and_return('fake-sha256-checksum')
        allow_any_instance_of(Bosh::AzureCloud::ComputeGalleryManager).to receive(:flock).and_yield
      end

      it 'creates a new gallery image through compute gallery manager' do
        stemcell_manager2.create_stemcell('fake-image-path', stemcell_properties)

        expect(azure_client).to have_received(:get_gallery_image_definition)
        expect(azure_client).to have_received(:create_gallery_image_definition)
        expect(azure_client).to have_received(:create_update_gallery_image_version)
      end

      it 'preserves original stemcell properties' do
        original_props = stemcell_properties.dup
        stemcell_manager2.create_stemcell('fake-image-path', stemcell_properties)
        expect(stemcell_properties).to eq(original_props)
      end
    end
  end

  describe '#delete_stemcell' do
    let(:user_images) do
      [
        { name: "#{stemcell_uuid}-postfix" }, # New format
        { name: "#{stemcell_name}-postfix" }, # Old format
        { name: "prefix-#{stemcell_name}" },
        { name: "prefix-#{stemcell_name}-postfix" }
      ]
    end

    let(:storage_accounts) do
      [
        { name: 'foo' },
        { name: 'bar' }
      ]
    end

    let(:entities) do
      [
        {
          'PartitionKey' => stemcell_name,
          'RowKey' => 'fake-storage-account-name',
          'Status' => 'success',
          'Timestamp' => Time.new
        }
      ]
    end

    before do
      allow(azure_client).to receive(:list_user_images)
        .and_return(user_images)
      allow(azure_client).to receive(:list_storage_accounts)
        .and_return(storage_accounts)
      allow(table_manager).to receive(:has_table?)
        .and_return(true)
      allow(blob_manager).to receive(:get_blob_properties)
        .and_return('foo' => 'bar') # The blob properties are not nil, which means the stemcell exists
      allow(table_manager).to receive(:query_entities)
        .and_return(entities)
    end

    context 'when use_default_account_for_cleaning is false' do
      it 'deletes all stemcells with the given stemcell name in all storage accounts' do
        # Delete the user images whose prefix is the stemcell_uuid or stemcell_name
        expect(azure_client).to receive(:delete_user_image)
          .with("#{stemcell_uuid}-postfix").once
        expect(azure_client).to receive(:delete_user_image)
          .with("#{stemcell_name}-postfix").once

        # Delete all stemcells with the given stemcell name in all storage accounts
        expect(blob_manager).to receive(:delete_blob).twice

        # Delete all records whose PartitionKey is the given stemcell name
        allow(table_manager).to receive(:delete_entity)

        stemcell_manager2.delete_stemcell(stemcell_name)
      end
    end

    context 'when compute gallery is enabled' do
      let(:blob_name) { "#{stemcell_name}.vhd" }
      let(:stemcell_container) { 'stemcell' }
      let(:location) { 'fake-location' }
      let(:gallery_name) { 'fake-gallery' }
      let(:image_definition) { 'fake-image-definition' }
      let(:image_version) { 'fake-version' }
      let(:azure_config) do
        Bosh::AzureCloud::AzureConfig.new(
          'compute_gallery_name' => gallery_name,
          'location' => location
        )
      end

      before do
        allow(azure_client).to receive(:delete_user_image)
        allow(blob_manager).to receive(:delete_blob)
        allow(azure_client).to receive(:delete_gallery_image_version)
        allow(table_manager).to receive(:delete_entity)
      end

      it 'deletes the gallery image version and the blob' do
        gallery_image_with_tags = {
          :gallery_name => gallery_name,
          :image_definition => image_definition,
          :name => image_version,
          :location => location,
          :tags => { 'stemcell_references' => stemcell_name, 'stemcell_name' => stemcell_name }
        }
        expect(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
          .with(gallery_name, stemcell_name)
          .and_return(gallery_image_with_tags)

        stemcell_manager2.delete_stemcell(stemcell_name)

        expect(azure_client).to have_received(:delete_gallery_image_version).with(gallery_name, image_definition, image_version)
        expect(blob_manager).to have_received(:delete_blob).with('foo', stemcell_container, blob_name).once
        expect(blob_manager).to have_received(:delete_blob).with('bar', stemcell_container, blob_name).once
      end

      context 'when image cannot be found by tags' do
        it 'skips deleting gallery image but deletes the blob' do
          allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(nil)

          stemcell_manager2.delete_stemcell(stemcell_name)

          expect(azure_client).not_to have_received(:delete_gallery_image_version)
          expect(blob_manager).to have_received(:delete_blob).twice
        end
      end

      context 'when stemcell name is not in the gallery image tags' do
        let(:gallery_image_without_name) do
          {
            :gallery_name => gallery_name,
            :image_definition => image_definition,
            :name => image_version,
            :location => location,
            :tags => {
              'stemcell_references' => 'other-stemcell-name',
              'stemcell_name' => 'other-stemcell-name'
            }
          }
        end

        before do
          allow(azure_client).to receive(:create_update_gallery_image_version)
        end

        it 'does not modify the gallery image' do
          expect(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
            .with(gallery_name, stemcell_name)
            .and_return(gallery_image_without_name)

          stemcell_manager2.delete_stemcell(stemcell_name)

          expect(azure_client).not_to have_received(:delete_gallery_image_version)
          expect(azure_client).not_to have_received(:create_update_gallery_image_version)
          expect(blob_manager).to have_received(:delete_blob).twice
        end
      end
    end
  end

  describe '#has_stemcell?' do
    context 'when the storage account has the stemcell' do
      it 'should return true' do
        expect(blob_manager).to receive(:get_blob_properties)
          .and_return({})

        expect(
          stemcell_manager2.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(true)
      end
    end

    context "when the storage account doesn't have the stemcell" do
      it 'should return false' do
        expect(blob_manager).to receive(:get_blob_properties)
          .and_return(nil)

        expect(
          stemcell_manager2.has_stemcell?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_name)
        ).to be(false)
      end
    end
  end

  describe '#get_user_image_info' do
    let(:storage_account_type) { 'Standard_LRS' }
    let(:location) { 'SoutheastAsia' }
    let(:user_image_name_deprecated) { "#{stemcell_name}-#{storage_account_type}-#{location}" }
    let(:user_image_name) { "#{stemcell_uuid}-S-#{location}" }
    let(:user_image_id) { 'fake-user-image-id' }
    let(:tags) do
      {
        'foo' => 'bar'
      }
    end
    let(:user_image) do
      {
        id: user_image_id,
        tags: tags
      }
    end

    # CPI will try to delete the user image with the old format name no matter it exists
    before do
      allow(azure_client).to receive(:delete_user_image).with(user_image_name_deprecated)
    end

    context 'when compute gallery is enabled' do
      let(:location) { 'fake-location' }
      let(:gallery_name) { 'fake-gallery' }
      let(:image_definition) { 'fake-image-definition' }
      let(:image_version) { 'fake-version' }
      let(:azure_config) do
        Bosh::AzureCloud::AzureConfig.new(
          'compute_gallery_name' => gallery_name,
          'location' => location
        )
      end
      let(:gallery_image) do
        {
          id: 'fake-gallery-id',
          gallery_name: gallery_name,
          image_definition: image_definition,
          name: image_version,
          location: location,
          tags: {
            'stemcell_name' => stemcell_name,
            'version' => '1.0'
          },
          target_regions: [location],
          replica_count: 3
        }
      end

      it 'returns gallery image info with complete metadata' do
        allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(gallery_image)
        expect(azure_client).not_to receive(:create_update_gallery_image_version)

        stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)

        expect(stemcell_info.uri).to eq('fake-gallery-id')
        expect(stemcell_info.metadata).to eq(gallery_image[:tags])
        expect(stemcell_info.metadata['stemcell_name']).to eq(stemcell_name)
      end

      context 'when gallery image cannot be found due to missing metadata on the blob' do
        it 'falls back to user image' do
          allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(nil)
          allow(blob_manager).to receive(:get_blob_metadata).and_return(nil)
          allow(azure_client).to receive(:get_user_image_by_name).and_return({ id: 'fake-id', tags: {} }).and_return({ id: 'fake-id', tags: {} })

          stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)

          expect(stemcell_info.uri).to eq('fake-id')
        end
      end

      context 'when gallery image does not exist, but image metadata exist on the blob' do
        let(:stemcell_blob_metadata) do
          {
            'compute_gallery_name'             => gallery_name,
            'compute_gallery_image_definition' => image_definition,
            'image'                            => JSON.dump({version: image_version}),
            'location'                         => location,
            'os_type'                          => 'linux',
          }
        end
        let(:default_storage_account) { { name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME } }

        it 'creates a new image' do
          allow(storage_account_manager).to receive(:default_storage_account).and_return(default_storage_account)
          allow(blob_manager).to receive(:get_blob_metadata)
            .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, 'stemcell', "#{stemcell_name}.vhd")
            .and_return(stemcell_blob_metadata)
          allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(nil)
          allow(azure_client).to receive(:get_gallery_image_version)
            .with(gallery_name, image_definition, image_version)
            .and_return(nil)
          allow(blob_manager).to receive(:get_blob_uri).and_return('fake-blob-uri')
          expect(azure_client).to receive(:get_gallery_image_definition).with(gallery_name, image_definition)
          expect(azure_client).to receive(:create_gallery_image_definition).with(gallery_name, image_definition, anything)
          expect(azure_client).to receive(:create_update_gallery_image_version).with(gallery_name, image_definition, image_version, anything).and_return(gallery_image)

          stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)

          expect(stemcell_info.uri).to eq('fake-gallery-id')
          expect(stemcell_info.metadata).to eq(gallery_image[:tags])
        end
      end

      context 'when gallery image exists, but is not replicated to the target location' do
        let(:other_location) { "other-#{location}" }

        it 'updates the image with missing location' do
          updated_image = gallery_image.dup
          updated_image[:target_regions] = [location, other_location]
          allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(gallery_image)
          allow(azure_client).to receive(:create_update_gallery_image_version).and_return(updated_image)

          stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, other_location)

          expect(azure_client).to have_received(:create_update_gallery_image_version)
            .with(gallery_name, image_definition, image_version, hash_including('target_regions' => [location, other_location]))
        end
      end

      context 'when gallery image exists, but replica count differs from config' do
        let(:expected_replica_count) { 10 }
        let(:azure_config) do
          Bosh::AzureCloud::AzureConfig.new(
            'compute_gallery_name' => gallery_name,
            'compute_gallery_replicas' => expected_replica_count,
            'location' => location
          )
        end

        it 'updates the image with correct replica count' do
          allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name).and_return(gallery_image)
          allow(azure_client).to receive(:create_update_gallery_image_version).and_return(gallery_image)

          stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)

          expect(azure_client).to have_received(:create_update_gallery_image_version)
            .with(gallery_name, image_definition, image_version, hash_including('replica_count' => expected_replica_count))
        end
      end
    end

    context 'when the user image already exists' do
      before do
        allow(azure_client).to receive(:get_user_image_by_name)
          .with(user_image_name)
          .and_return(user_image)
      end

      it 'should return the user image information' do
        expect(storage_account_manager).not_to receive(:default_storage_account)

        stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)

        expect(stemcell_info.uri).to eq(user_image_id)
        expect(stemcell_info.metadata).to eq(tags)
      end
    end

    context "when the user image doesn't exist" do
      context "when the stemcell doesn't exist in the default storage account" do
        let(:default_storage_account) do
          {
            name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
          }
        end

        before do
          allow(azure_client).to receive(:get_user_image_by_name)
            .with(user_image_name)
            .and_return(nil)
          allow(storage_account_manager).to receive(:default_storage_account)
            .and_return(default_storage_account)
          allow(blob_manager).to receive(:get_blob_properties)
            .and_return(nil) # The blob properties are nil, which means the stemcell doesn't exist
        end

        it 'should raise an error' do
          expect do
            stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
          end.to raise_error(/Failed to get user image for the stemcell '#{stemcell_name}'/)
        end
      end

      context 'when the stemcell exists in the default storage account' do
        let(:stemcell_container) { 'stemcell' }
        let(:stemcell_blob_uri) { 'fake-blob-url' }
        let(:stemcell_blob_metadata) { { 'foo' => 'bar' } }
        let(:user_image) do
          {
            id: user_image_id,
            tags: tags,
            provisioning_state: 'Succeeded'
          }
        end

        before do
          allow(azure_client).to receive(:get_user_image_by_name)
            .with(user_image_name)
            .and_return(nil, user_image) # The first return value nil means the user image doesn't exist, the second one user_image is returned after the image is created.
          allow(blob_manager).to receive(:get_blob_properties)
            .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
            .and_return('foo' => 'bar') # The stemcell exists in the default storage account
        end

        context 'when the location of the default storage account is the targeted location' do
          let(:default_storage_account) do
            {
              name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              location: location
            }
          end

          before do
            allow(storage_account_manager).to receive(:default_storage_account)
              .and_return(default_storage_account)
            allow(blob_manager).to receive(:get_blob_uri)
              .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
              .and_return(stemcell_blob_uri)
            allow(blob_manager).to receive(:get_blob_metadata)
              .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
              .and_return(stemcell_blob_metadata)
          end

          context 'when the lock is got for the first time' do
            before do
              allow(azure_client).to receive(:get_user_image_by_name)
                .with(user_image_name)
                .and_return(nil, nil, user_image) # The first and the second return value nil means the user image doesn't exist, the third one user_image is returned after the image is created.
            end

            it 'should get the stemcell from the default storage account, create a new user image and return the user image information' do
              expect(azure_client).not_to receive(:list_storage_accounts)
              expect(stemcell_manager2).to receive(:flock).with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX).and_call_original
              expect(stemcell_manager2).to receive(:flock).with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX).and_call_original
              expect(azure_client).to receive(:create_user_image)
              stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              expect(stemcell_info.uri).to eq(user_image_id)
              expect(stemcell_info.metadata).to eq(tags)
            end
          end

          context 'when the lock is got, but the image is already created by other process' do
            before do
              allow(azure_client).to receive(:get_user_image_by_name)
                .with(user_image_name)
                .and_return(nil, user_image) # The first return value nil means the user image doesn't exist, the second one user_image is returned after the image is created.
            end

            it 'should get the stemcell from the default storage account, get the user image and return image information' do
              expect(azure_client).not_to receive(:list_storage_accounts)
              expect(stemcell_manager2).to receive(:flock).with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX).and_call_original
              expect(stemcell_manager2).to receive(:flock).with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX).and_call_original
              expect(azure_client).not_to receive(:create_user_image)
              stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              expect(stemcell_info.uri).to eq(user_image_id)
              expect(stemcell_info.metadata).to eq(tags)
            end
          end
        end

        context 'when the location of the default storage account is not the targeted location' do
          let(:default_storage_account) do
            {
              name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              location: "#{location}-different"
            }
          end

          before do
            allow(storage_account_manager).to receive(:default_storage_account)
              .and_return(default_storage_account)
          end

          context 'when the storage account with tags exists in the specified location' do
            let(:existing_storage_account_name) { 'existing-storage-account-name-other-than-default-storage-account' }
            let(:storage_account) do
              {
                name: existing_storage_account_name,
                location: location,
                tags: STEMCELL_STORAGE_ACCOUNT_TAGS
              }
            end

            before do
              allow(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
                .and_return(storage_account)
              # The following two allows are for get_stemcell_info of stemcell_manager.rb
              allow(blob_manager).to receive(:get_blob_uri)
                .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                .and_return(stemcell_blob_uri)
              allow(blob_manager).to receive(:get_blob_metadata)
                .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                .and_return(stemcell_blob_metadata)
            end

            context 'when the stemcell exists in the exising storage account, but the image does not exist' do
              before do
                allow(blob_manager).to receive(:get_blob_properties)
                  .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return('foo' => 'bar') # The stemcell exists in the existing storage account
                allow(azure_client).to receive(:get_user_image_by_name)
                  .with(user_image_name)
                  .and_return(nil, nil, user_image) # The first and the second return value nil means the user image doesn't exist, the third one user_image is returned after the image is created.
              end

              it 'should create a new user image and return the user image information' do
                expect(blob_manager).not_to receive(:get_sas_blob_uri)
                  .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
                expect(blob_manager).not_to receive(:copy_blob)
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{existing_storage_account_name}", File::LOCK_EX)
                  .and_call_original
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                  .and_call_original
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                  .and_call_original
                expect(azure_client).to receive(:create_user_image)
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end

            context "when the stemcell doesn't exist in the exising storage account" do
              before do
                allow(blob_manager).to receive(:get_blob_properties)
                  .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return(nil) # The stemcell doesn't exist in the existing storage account
              end

              context 'when copying blob is successful' do
                before do
                  allow(azure_client).to receive(:get_user_image_by_name)
                    .with(user_image_name)
                    .and_return(nil, nil, user_image) # The first and the second return value nil means the user image doesn't exist, the third one user_image is returned after the image is created.
                end

                it 'should copy the stemcell from default storage account to an existing storage account, create a new user image and return the user image information' do
                  expect(blob_manager).to receive(:get_sas_blob_uri)
                    .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
                    .and_return(stemcell_blob_uri)
                  expect(stemcell_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{existing_storage_account_name}", File::LOCK_EX)
                    .and_call_original
                  expect(stemcell_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                    .and_call_original
                  expect(stemcell_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                    .and_call_original
                  expect(blob_manager).to receive(:copy_blob)
                    .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
                  expect(azure_client).to receive(:create_user_image)
                  stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  expect(stemcell_info.uri).to eq(user_image_id)
                  expect(stemcell_info.metadata).to eq(tags)
                end
              end

              context 'when copying blob raises an error' do
                before do
                  allow(blob_manager).to receive(:get_sas_blob_uri)
                    .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
                    .and_return(stemcell_blob_uri)
                  expect(blob_manager).to receive(:copy_blob)
                    .with(existing_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)
                    .and_raise('Error when copying blobs')
                end

                it 'should raise an error' do
                  expect(stemcell_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                    .and_call_original
                  expect(stemcell_manager2).to receive(:flock)
                    .with("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{existing_storage_account_name}", File::LOCK_EX)
                    .and_call_original
                  expect do
                    stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  end.to raise_error(/Error when copying blobs/)
                end
              end
            end
          end

          context "when the storage account with tags doesn't exist in the specified location" do
            context 'when it fails to create the new storage account' do
              context 'when an error is thrown when creating the new storage account' do
                before do
                  allow(storage_account_manager).to receive(:find_storage_account_by_tags).and_return(nil)
                  allow(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
                    .and_raise('Error when creating storage account')
                end

                it 'raise an error' do
                  expect do
                    stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                  end.to raise_error(/Error when creating storage account/)
                end
              end
            end

            context 'when it creates the new storage account successfully, and copies the stemcell from default storage account to the new storage account' do
              let(:new_storage_account_name) { '54657da5936725e199fd616e' }
              let(:storage_account) do
                {
                  name: new_storage_account_name,
                  location: location,
                  tags: STEMCELL_STORAGE_ACCOUNT_TAGS
                }
              end

              before do
                # check storage account
                allow(storage_account_manager).to receive(:find_storage_account_by_tags).and_return(nil)

                # The following two allows are for get_stemcell_info of stemcell_manager.rb
                allow(blob_manager).to receive(:get_blob_uri)
                  .with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return(stemcell_blob_uri)
                allow(blob_manager).to receive(:get_blob_metadata)
                  .with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return(stemcell_blob_metadata)
                allow(blob_manager).to receive(:get_blob_properties)
                  .with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return(nil) # The stemcell doesn't exist in the new storage account

                # Copy blob
                allow(blob_manager).to receive(:get_sas_blob_uri)
                  .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
                  .and_return(stemcell_blob_uri)
                allow(blob_manager).to receive(:copy_blob)
                  .with(new_storage_account_name, stemcell_container, "#{stemcell_name}.vhd", stemcell_blob_uri)

                # check image
                allow(azure_client).to receive(:get_user_image_by_name)
                  .with(user_image_name)
                  .and_return(nil, nil, user_image) # The first and the second return value nil means the user image doesn't exist, the third one user_image is returned after the image is created.
              end

              it 'should create a new user image and return the user image information' do
                expect(storage_account_manager).to receive(:get_or_create_storage_account_by_tags)
                  .with(STEMCELL_STORAGE_ACCOUNT_TAGS, storage_account_type, 'Storage', location, ['stemcell'], false)
                  .and_return(storage_account)
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_COPY_STEMCELL}-#{stemcell_name}-#{new_storage_account_name}", File::LOCK_EX)
                  .and_call_original
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                  .and_call_original
                expect(stemcell_manager2).to receive(:flock)
                  .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                  .and_call_original
                expect(blob_manager).to receive(:copy_blob)
                expect(azure_client).to receive(:create_user_image)
                stemcell_info = stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
                expect(stemcell_info.uri).to eq(user_image_id)
                expect(stemcell_info.metadata).to eq(tags)
              end
            end
          end
        end

        context 'When CPI is going to create user image' do
          let(:default_storage_account) do
            {
              name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              location: location
            }
          end

          before do
            allow(storage_account_manager).to receive(:default_storage_account)
              .and_return(default_storage_account)
            allow(blob_manager).to receive(:get_blob_properties)
              .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
              .and_return('foo' => 'bar') # The stemcell exists in the default storage account
            allow(blob_manager).to receive(:get_blob_uri)
              .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
              .and_return(stemcell_blob_uri)
            allow(blob_manager).to receive(:get_blob_metadata)
              .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd")
              .and_return(stemcell_blob_metadata)
          end

          context 'when the user image is not created successfully' do
            before do
              allow(azure_client).to receive(:get_user_image_by_name)
                .with(user_image_name)
                .and_return(nil, nil, nil) # The first and second return value nil means the user image doesn't exist, the third nil means that the user image can't be found after creation.
            end

            it 'should raise an error' do
              expect(stemcell_manager2).to receive(:flock)
                .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                .and_call_original
              expect(stemcell_manager2).to receive(:flock)
                .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                .and_call_original
              expect(azure_client).to receive(:create_user_image)

              expect do
                stemcell_manager2.get_user_image_info(stemcell_name, storage_account_type, location)
              end.to raise_error(/get_user_image: Can not find a user image with the name '#{user_image_name}'/)
            end
          end

          context 'when the user image is created successfully' do
            let(:user_image) do
              {
                id: user_image_id,
                tags: tags,
                provisioning_state: 'Succeeded'
              }
            end

            before do
              allow(azure_client).to receive(:get_user_image_by_name)
                .with(user_image_name)
                .and_return(user_image)
              allow(azure_client).to receive(:get_user_image_by_name)
                .with(user_image_name)
                .and_return(nil, nil, user_image) # The first and second return value nil means the user image doesn't exist, the third nil means that the user image can't be found after creation.
            end

            it 'should return the new user image' do
              expect(stemcell_manager2).to receive(:flock)
                .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                .and_call_original
              expect(stemcell_manager2).to receive(:flock)
                .with("#{CPI_LOCK_CREATE_USER_IMAGE}-#{user_image_name}", File::LOCK_EX)
                .and_call_original
              expect(azure_client).to receive(:create_user_image)
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
