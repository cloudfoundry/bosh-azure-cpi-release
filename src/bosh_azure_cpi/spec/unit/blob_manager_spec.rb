# frozen_string_literal: true

require 'spec_helper'
describe Bosh::AzureCloud::BlobManager do
  let(:azure_config) { mock_azure_config }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:blob_manager) { Bosh::AzureCloud::BlobManager.new(azure_config, azure_client) }

  let(:container_name) { 'fake-container-name' }
  let(:blob_name) { 'fake-blob-name' }
  let(:keys) { ['fake-key-1', 'fake-key-2'] }

  let(:azure_storage_client) { instance_double(Azure::Storage::Common::Client) }
  let(:blob_service) { instance_double(Azure::Storage::Blob::BlobService) }
  let(:customized_retry) { instance_double(Bosh::AzureCloud::CustomizedRetryPolicyFilter) }
  let(:storage_dns_suffix) { 'fake-storage-dns-suffix' }
  let(:blob_host) { "https://#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}.blob.#{storage_dns_suffix}" }
  let(:storage_account) do
    {
      id: 'foo',
      name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
      location: 'bar',
      provisioning_state: 'bar',
      account_type: 'foo',
      storage_blob_host: blob_host
    }
  end
  let(:request_id) { 'fake-client-request-id' }
  let(:options) do
    {
      request_id: request_id
    }
  end
  let(:metadata) { {} }
  let(:sas_generator) { instance_double(Azure::Storage::Common::Core::Auth::SharedAccessSignature) }

  before do
    allow(Azure::Storage::Common::Client).to receive(:create)
      .and_return(azure_storage_client)
    allow(Bosh::AzureCloud::AzureClient).to receive(:new)
      .and_return(azure_client)
    allow(Azure::Storage::Common::Core::Auth::SharedAccessSignature).to receive(:new)
      .and_return(sas_generator)
    allow(azure_client).to receive(:get_storage_account_keys_by_name)
      .and_return(keys)
    allow(azure_client).to receive(:get_storage_account_by_name)
      .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
      .and_return(storage_account)
    allow(azure_storage_client).to receive(:storage_blob_host).and_return(blob_host)
    allow(Azure::Storage::Blob::BlobService).to receive(:new).with({ client: azure_storage_client })
                                                             .and_return(blob_service)
    allow(Bosh::AzureCloud::CustomizedRetryPolicyFilter).to receive(:new)
      .and_return(customized_retry)
    allow(blob_service).to receive(:with_filter).with(customized_retry)
    allow(SecureRandom).to receive(:uuid).and_return(request_id)
  end

  describe '#delete_blob' do
    it 'delete the blob' do
      expect(blob_service).to receive(:delete_blob)
        .with(container_name, blob_name, { delete_snapshots: :include, request_id: request_id })

      expect do
        blob_manager.delete_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      end.not_to raise_error
    end
  end

  describe '#get_sas_blob_uri' do
    let(:now) { Time.new }
    let(:mock_sas_token) { 'mock_sas_token' }

    before do
      allow(Time).to receive(:new).and_return(now)
      allow(sas_generator).to receive(:generate_service_sas_token)
        .with(
          "#{container_name}/#{blob_name}",
          service: 'b', resource: 'b', permissions: 'r', protocol: 'https',
          expiry: (now + (3600 * 24 * 7)).utc.iso8601
        ).and_return(mock_sas_token)
    end

    it 'gets the sas uri of the blob' do
      expect(
        blob_manager.get_sas_blob_uri(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq("#{blob_host}/#{container_name}/#{blob_name}?#{mock_sas_token}")
    end
  end

  describe '#get_blob_uri' do
    it 'gets the uri of the blob' do
      expect(
        blob_manager.get_blob_uri(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq("#{blob_host}/#{container_name}/#{blob_name}")
    end
  end

  describe '#delete_blob_snapshot' do
    it 'delete the blob snapshot' do
      snapshot_time = 10

      expect(blob_service).to receive(:delete_blob)
        .with(container_name, blob_name, { snapshot: snapshot_time, request_id: request_id })

      expect do
        blob_manager.delete_blob_snapshot(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, snapshot_time)
      end.not_to raise_error
    end
  end

  describe '#get_blob_size_in_bytes' do
    let(:blob) { instance_double('Blob') }

    before do
      allow(blob_service).to receive(:get_blob_properties)
        .with(container_name, blob_name)
        .and_return(blob)
      allow(blob).to receive(:properties).and_return(content_length: 1024)
    end

    it 'gets the size of the blob' do
      expect(
        blob_manager.get_blob_size_in_bytes(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq(1024)
    end
  end

  describe '#create_page_blob' do
    let(:metadata) do
      {
        'property' => 'fake-metadata'
      }
    end
    let(:options) do
      {
        request_id: request_id,
        timeout: 120,
        metadata: metadata
      }
    end

    context 'when normal page blob' do
      before(:context) do
        @file_path = '/tmp/fake_image'
        File.open(@file_path, 'wb') { |f| f.write('Hello CloudFoundry!') }
      end

      after(:context) do
        File.delete(@file_path) if File.exist?(@file_path)
      end

      context 'when uploading page blob succeeds' do
        before do
          allow(blob_service).to receive(:put_blob_pages)
          allow(blob_service).to receive(:delete_blob)
        end

        it 'raise no error' do
          expect(blob_service).to receive(:create_page_blob)
            .with(container_name, blob_name, kind_of(Numeric), options)

          expect do
            blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
          end.not_to raise_error
        end
      end

      context 'when uploading page blob fails' do
        before do
          allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
        end

        it 'should raise an error' do
          expect do
            blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
          end.to raise_error(/Failed to upload page blob/)
        end
      end

      context 'when retry reached max times' do
        before do
          allow(blob_service).to receive(:put_blob_pages).and_raise('put blob pages failed')
          allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
        end

        it 'should raise an error' do
          expect(blob_service).to receive(:create_page_blob)
            .with(container_name, blob_name, kind_of(Numeric), options)
          expect(blob_service).to receive(:delete_blob)
          expect do
            blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
          end.to raise_error(/put blob pages failed/)
        end
      end
    end

    context 'when empty page blob' do
      before do
        @empty_file_path = '/tmp/empty_content_image'
        MAX_CHUNK_SIZE = 2 * 1024 * 1024 # 2MB
        @empty_chunk_content = Array.new(MAX_CHUNK_SIZE, 0).pack('c*')
        File.open(@empty_file_path, 'wb') { |f| f.write(@empty_chunk_content) }
      end

      after do
        File.delete(@empty_file_path) if File.exist?(@empty_file_path)
      end

      it 'should not call put_blob_pages' do
        expect(blob_service).to receive(:create_page_blob)
          .with(container_name, blob_name, kind_of(Numeric), options)
        expect(blob_service).not_to receive(:put_blob_pages)
        expect do
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @empty_file_path, blob_name, metadata)
        end.not_to raise_error
      end
    end
  end

  describe '#create_empty_page_blob' do
    let(:metadata) do
      {
        'property' => 'fake-metadata'
      }
    end
    let(:options) do
      {
        request_id: request_id,
        timeout: 120,
        metadata: metadata
      }
    end

    context 'when create empty page blob succeeds' do
      it 'raise no error' do
        expect(blob_service).to receive(:create_page_blob)
          .with(container_name, blob_name, 1024, options)

        expect do
          blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
        end.not_to raise_error
      end
    end

    context 'when create empty page blob fails' do
      before do
        allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
      end

      it 'should raise an error' do
        expect do
          blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
        end.to raise_error(/Failed to create empty page blob/)
      end
    end

    context 'when container not exists' do
      let(:options) do
        {
          request_id: request_id
        }
      end

      before do
        times = 0
        allow(blob_service).to receive(:create_page_blob) do
          if times.zero?
            times += 1
            raise 'ContainerNotFound'
          end
          true
        end
      end

      context 'when no other one created the container' do
        it 'should create container and retry one time' do
          expect(blob_service).to receive(:create_container)
            .with(container_name, options)
            .and_return(true)
          expect(blob_service).to receive(:create_page_blob)
            .twice
          expect do
            blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
          end.not_to raise_error
        end
      end

      context 'when other one created the container' do
        it 'should use the created container' do
          expect(blob_service).to receive(:create_container)
            .with(container_name, options)
            .and_raise 'ContainerAlreadyExists'
          expect(blob_service).to receive(:create_page_blob)
            .twice
          expect do
            blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
          end.not_to raise_error
        end
      end
    end
  end

  describe '#create_empty_vhd_blob' do
    context 'when creating empty vhd blob succeeds' do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:put_blob_pages)
      end

      it 'raise no error' do
        expect do
          blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1024)
        end.not_to raise_error
      end
    end

    context 'when creating empty vhd blob fails' do
      context 'blob is not created' do
        before do
          allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
        end

        it 'should raise an error and do not delete blob' do
          expect(blob_service).not_to receive(:delete_blob)

          expect do
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1024)
          end.to raise_error(/Failed to create empty vhd blob/)
        end
      end

      context 'blob is created' do
        before do
          allow(blob_service).to receive(:create_page_blob)
          allow(blob_service).to receive(:put_blob_pages).and_raise(StandardError)
        end

        it 'should raise an error and delete blob' do
          expect(blob_service).to receive(:delete_blob)

          expect do
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1024)
          end.to raise_error(/Failed to create empty vhd blob/)
        end
      end
    end
  end

  describe '#create_vhd_page_blob' do
    before(:context) do
      @file_path = '/tmp/fake_image'
      @empty_chunk_content = Array.new(2 * 1024 * 1024, 0).pack('c*')
      File.open(@file_path, 'wb') { |f| f.write(@empty_chunk_content) }
    end

    after(:context) do
      File.delete(@file_path) if File.exist?(@file_path)
    end

    context 'when creating vhd page blob succeeds' do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:put_blob_pages)
      end

      it 'raise no error' do
        expect do
          blob_manager.create_vhd_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
        end.not_to raise_error
      end
    end

    context 'when creating vhd page blob failed' do
      context 'page blob created' do
        before do
          allow(blob_service).to receive(:create_page_blob)
          allow(blob_service).to receive(:put_blob_pages).and_raise(StandardError)
        end

        it 'page blob should be deleted' do
          expect(blob_service).to receive(:delete_blob)
          expect do
            blob_manager.create_vhd_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
          end.to raise_error(/Failed to upload page blob/)
        end
      end

      context 'page blob not created' do
        before do
          allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
        end

        it 'page blob should be deleted' do
          expect(blob_service).not_to receive(:delete_blob)
          expect do
            blob_manager.create_vhd_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
          end.to raise_error(/Failed to upload page blob/)
        end
      end
    end
  end

  describe '#get_blob_properties' do
    context 'when storage account does not exist' do
      before do
        allow(azure_client).to receive(:get_storage_account_by_name)
          .with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
          .and_return(nil)
      end

      it 'should raise error' do
        expect do
          blob_manager.get_blob_properties(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        end.to raise_error("_initialize_blob_client: Storage account '#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}' not found")
      end
    end

    context 'when blob exists' do
      let(:blob) { instance_double(Azure::Storage::Blob::Blob) }
      let(:properties) { { 'foo' => 'bar' } }

      before do
        allow(blob).to receive(:properties).and_return(properties)
      end

      it 'should get the properties of the blob' do
        expect(blob_service).to receive(:get_blob_properties)
          .with(container_name, blob_name, options)
          .and_return(blob)

        expect(
          blob_manager.get_blob_properties(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(properties)
      end
    end

    context 'when blob does not exist' do
      before do
        allow(blob_service).to receive(:get_blob_properties)
          .and_raise('(404)')
      end

      it 'should return nil' do
        expect(
          blob_manager.get_blob_properties(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(nil)
      end
    end
  end

  describe '#get_blob_metadata' do
    context 'when blob exists' do
      let(:blob) { instance_double(Azure::Storage::Blob::Blob) }
      let(:metadata) { { 'os_type' => 'fake-os-type' } }

      before do
        allow(blob).to receive(:metadata).and_return(metadata)
      end

      it 'should get metadata of the blob' do
        expect(blob_service).to receive(:get_blob_metadata)
          .with(container_name, blob_name, options)
          .and_return(blob)
        expect(
          blob_manager.get_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to eq(metadata)
      end
    end

    context 'when blob does not exist' do
      before do
        allow(blob_service).to receive(:get_blob_metadata)
          .and_raise('(404)')
      end

      it 'should return nil' do
        expect(
          blob_manager.get_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(nil)
      end
    end
  end

  describe '#set_blob_metadata' do
    let(:metadata) do
      {
        'os_type' => 'fake-os-type',
        'integer' => 1024,
        'boolean' => true
      }
    end
    let(:encoded_metadata) do
      {
        'os_type' => 'fake-os-type',
        'integer' => '1024',
        'boolean' => 'true'
      }
    end

    context 'when blob exists' do
      it 'should set metadata successfully' do
        expect(blob_service).to receive(:set_blob_metadata)
          .with(container_name, blob_name, encoded_metadata, options)

        expect do
          blob_manager.set_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
        end.not_to raise_error
      end
    end

    context 'when blob not exists' do
      before do
        allow(blob_service).to receive(:set_blob_metadata)
          .and_raise('(404)')
      end

      it 'should raise error' do
        expect do
          blob_manager.set_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
        end.to raise_error(/(404)/)
      end
    end
  end

  describe '#list_blobs' do
    context 'when the container does not exist' do
      before do
        allow(blob_service).to receive(:list_blobs).and_return('The container does not exist')
      end

      it 'should return empty' do
        expect do
          blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        end.to raise_error(/The container does not exist/)
      end
    end

    context 'when the container is empty' do
      let(:tmp_blobs) { Azure::Storage::Common::Service::EnumerationResults.new }

      before do
        allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
      end

      it 'should return empty' do
        expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)).to be_empty
      end
    end

    context 'when the container is not empty' do
      context 'without continuation_token' do
        let(:tmp_blobs) do
          Azure::Storage::Common::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        end

        before do
          allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
        end

        it 'should return blobs' do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(1)
        end
      end

      context 'with continuation_token' do
        let(:tmp_blobs_1) do
          Azure::Storage::Common::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        end
        let(:tmp_blobs_2) do
          Azure::Storage::Common::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        end
        let(:continuation_token) { 'fake-token' }

        before do
          allow(blob_service).to receive(:list_blobs)
            .with(container_name, options).and_return(tmp_blobs_1)
          allow(tmp_blobs_1).to receive(:continuation_token).and_return(continuation_token)
          allow(blob_service).to receive(:list_blobs)
            .with(container_name, { marker: continuation_token, request_id: request_id })
            .and_return(tmp_blobs_2)
        end

        it 'should return blobs' do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(2)
        end
      end
    end
  end

  describe '#snapshot_blob' do
    it 'snapshots the blob' do
      snapshot_time = 10
      metadata = {}

      expect(blob_service).to receive(:create_blob_snapshot)
        .with(container_name, blob_name, { metadata: metadata, request_id: request_id })
        .and_return(snapshot_time)

      expect(
        blob_manager.snapshot_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
      ).to eq(snapshot_time)
    end
  end

  describe '#copy_blob' do
    let(:another_storage_account_name) { 'another-storage-account-name' }
    let(:source_blob_uri) { 'fake-source-blob-uri' }
    let(:another_storage_account) do
      {
        id: 'foo',
        name: another_storage_account_name,
        location: 'bar',
        provisioning_state: 'bar',
        account_type: 'foo',
        storage_blob_host: "https://another-storage-account.blob.#{storage_dns_suffix}"
      }
    end
    let(:blob) { instance_double(Azure::Storage::Blob::Blob) }

    before do
      allow(azure_client).to receive(:get_storage_account_by_name)
        .with(another_storage_account_name)
        .and_return(another_storage_account)
      allow(blob_service).to receive(:get_blob_properties).and_return(blob)
    end

    context 'when everything is fine' do
      context 'when copy status is success in the first response' do
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'success'])
        end

        it 'succeeds to copy the blob' do
          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.not_to raise_error
        end
      end

      context 'when copy status is success in the fourth response' do
        let(:first_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'pending',
            copy_status_description: 'fake-status-description',
            copy_progress: '1234/5678'
          }
        end
        let(:second_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'pending',
            copy_status_description: 'fake-status-description',
            copy_progress: '3456/5678'
          }
        end
        let(:third_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'pending',
            copy_status_description: 'fake-status-description',
            copy_progress: '5666/5678'
          }
        end
        let(:fourth_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'success',
            copy_status_description: 'fake-status-description',
            copy_progress: '5678/5678'
          }
        end

        before do
          allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties)
            .and_return(first_blob_properties, second_blob_properties, third_blob_properties, fourth_blob_properties)
        end

        it 'succeeds to copy the blob' do
          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.not_to raise_error
        end
      end

      context 'when container not exists and created successfully' do
        let(:options) do
          {
            request_id: request_id
          }
        end

        before do
          times = 0
          allow(blob_service).to receive(:copy_blob_from_uri) do
            if times.zero?
              times += 1
              raise 'ContainerNotFound'
            end
            ['fake-copy-id', 'success']
          end
        end

        context 'when no other one created the container' do
          it 'succeeds to copy the blob' do
            expect(blob_service).to receive(:create_container)
              .with(container_name, options)
              .and_return(true)
            expect(blob_service).to receive(:copy_blob_from_uri)
              .twice
            expect do
              blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
            end.not_to raise_error
          end
        end

        context 'when other one created the container' do
          it 'succeeds to copy the blob' do
            expect(blob_service).to receive(:create_container)
              .with(container_name, options)
              .and_raise 'ContainerAlreadyExists'
            expect(blob_service).to receive(:copy_blob_from_uri)
              .twice
            expect do
              blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
            end.not_to raise_error
          end
        end
      end
    end

    context 'when copy status is failed' do
      context 'when copy_blob_from_uri returns failed' do
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'failed'])
        end

        it 'fails to copy the blob' do
          expect(blob_service).to receive(:delete_blob).with(container_name, blob_name, options)

          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.to raise_error(/Failed to copy the blob/)
        end
      end

      context 'when copy status is failed in the second response' do
        let(:first_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'pending',
            copy_status_description: 'fake-status-description',
            copy_progress: '1234/5678'
          }
        end
        let(:second_blob_properties) do
          {
            copy_id: 'fake-copy-id',
            copy_status: 'failed',
            copy_status_description: 'fake-status-description'
          }
        end

        before do
          allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties)
            .and_return(first_blob_properties, second_blob_properties)
        end

        it 'fails to copy the blob' do
          expect(blob_service).to receive(:delete_blob).with(container_name, blob_name, options)

          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.to raise_error(/Failed to copy the blob/)
        end
      end
    end

    context 'when the progress of copying is interrupted' do
      context 'when copy id is nil' do
        let(:blob_properties) do
          {
            # copy_id is nil
            copy_status: 'interrupted'
          }
        end

        before do
          allow_any_instance_of(Object).to receive(:sleep).and_return(nil)
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).and_return(blob_properties)
        end

        it 'should raise an error' do
          expect(blob_service).to receive(:delete_blob)
            .with(container_name, blob_name, options)

          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.to raise_error %r{The progress of copying the blob #{source_blob_uri} to #{container_name}/#{blob_name} was interrupted}
        end
      end

      context 'when copy id does not match' do
        let(:blob_properties) do
          {
            copy_id: 'another-copy-id',
            copy_status: 'pending',
            copy_status_description: 'fake-status-description',
            copy_progress: '1234/5678'
          }
        end

        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).and_return(blob_properties)
        end

        it 'should raise an error' do
          expect(blob_service).to receive(:delete_blob)
            .with(container_name, blob_name, options)

          expect do
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          end.to raise_error %r{The progress of copying the blob #{source_blob_uri} to #{container_name}/#{blob_name} was interrupted}
        end
      end
    end

    context 'when unexpected error happens' do
      before do
        allow(blob_service).to receive(:copy_blob_from_uri).and_raise('Unexpected Error')
      end

      it 'succeeds to copy the blob' do
        expect do
          blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
        end.to raise_error(/Unexpected Error/)
      end
    end
  end
end

describe Bosh::AzureCloud::CustomizedRetryPolicyFilter do
  let(:customized_retry_policy_filter) { Bosh::AzureCloud::CustomizedRetryPolicyFilter.new }

  describe '#apply_retry_policy' do
    context 'when there is no error' do
      let(:retry_data) { {} }

      it 'should not set the retryable' do
        customized_retry_policy_filter.apply_retry_policy(retry_data)
        expect(retry_data[:retryable]).to be(nil)
      end
    end

    context 'when the error is neither OpenSSL::SSL::SSLError nor OpenSSL::X509::StoreError' do
      let(:retry_data) do
        {
          error: StandardError
        }
      end

      it 'should not set the retryable' do
        customized_retry_policy_filter.apply_retry_policy(retry_data)
        expect(retry_data[:retryable]).to be(nil)
      end
    end

    context 'when the error is OpenSSL::SSL::SSLError' do
      context 'when the error message is related to connection reset' do
        let(:retry_data) do
          {
            error: OpenSSL::SSL::SSLError.new('Connection reset by peer - SSL_connect')
          }
        end

        it 'should set the retryable to true' do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(true)
        end
      end

      context 'when the error message is not related to connection reset' do
        let(:retry_data) do
          {
            error: OpenSSL::SSL::SSLError.new('Some other error')
          }
        end

        it 'should not set the retryable' do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(nil)
        end
      end
    end

    context 'when the error is OpenSSL::X509::StoreError' do
      context 'when the error message is related to connection reset' do
        let(:retry_data) do
          {
            error: OpenSSL::X509::StoreError.new('Connection reset by peer - SSL_connect')
          }
        end

        it 'should set the retryable to true' do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(true)
        end
      end

      context 'when the error message is not related to connection reset' do
        let(:retry_data) do
          {
            error: OpenSSL::X509::StoreError.new('Some other error')
          }
        end

        it 'should not set the retryable' do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(nil)
        end
      end
    end
  end
end
