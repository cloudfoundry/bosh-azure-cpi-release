require 'spec_helper'

describe Bosh::AzureCloud::BlobManager do
  let(:azure_properties) { mock_azure_properties }
  let(:azure_client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:blob_manager) { Bosh::AzureCloud::BlobManager.new(azure_properties, azure_client2) }

  let(:container_name) { "fake-container-name" }
  let(:blob_name) { "fake-blob-name" }
  let(:keys) { ["fake-key-1", "fake-key-2"] }

  let(:azure_client) { instance_double(Azure::Storage::Client) }
  let(:blob_service) { instance_double(Azure::Storage::Blob::BlobService) }
  let(:customized_retry) { instance_double(Bosh::AzureCloud::CustomizedRetryPolicyFilter) }
  let(:blob_host) { "fake-blob-endpoint" }
  let(:storage_account) {
    {
      :id => "foo",
      :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
      :location => "bar",
      :provisioning_state => "bar",
      :account_type => "foo",
      :storage_blob_host => "fake-blob-endpoint",
      :storage_table_host => "fake-table-endpoint"
    }
  }
  let(:request_id) { 'fake-client-request-id' }
  let(:options) {
    {
      :request_id => request_id
    }
  }
  let(:metadata) { {} }

  before do
    allow(Azure::Storage::Client).to receive(:create).
      and_return(azure_client)
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(azure_client2)
    allow(azure_client2).to receive(:get_storage_account_keys_by_name).
      and_return(keys)
    allow(azure_client2).to receive(:get_storage_account_by_name).
      with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).
      and_return(storage_account)
    allow(azure_client).to receive(:storage_blob_host=)
    allow(azure_client).to receive(:storage_blob_host).and_return(blob_host)
    allow(azure_client).to receive(:blob_client).
      and_return(blob_service)
    allow(Bosh::AzureCloud::CustomizedRetryPolicyFilter).to receive(:new).
      and_return(customized_retry)
    allow(blob_service).to receive(:with_filter).with(customized_retry)
    allow(SecureRandom).to receive(:uuid).and_return(request_id)
  end

  describe "#delete_blob" do
    it "delete the blob" do
      expect(blob_service).to receive(:delete_blob).
        with(container_name, blob_name, {
          :delete_snapshots => :include,
          :request_id => request_id
        })

      expect {
        blob_manager.delete_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      }.not_to raise_error
    end
  end

  describe "#get_blob_uri" do
    it "gets the uri of the blob" do
      expect(
        blob_manager.get_blob_uri(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq("#{blob_host}/#{container_name}/#{blob_name}")
    end
  end  

  describe "#delete_blob_snapshot" do
    it "delete the blob snapshot" do
      snapshot_time = 10

      expect(blob_service).to receive(:delete_blob).
        with(container_name, blob_name, {
          :snapshot => snapshot_time,
          :request_id => request_id
        })

      expect {
        blob_manager.delete_blob_snapshot(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, snapshot_time)
      }.not_to raise_error
    end
  end  

  describe "#get_blob_size_in_bytes" do
    let(:blob) { instance_double("Blob") }

    before do
      allow(blob_service).to receive(:get_blob_properties).
        with(container_name, blob_name).
        and_return(blob) 
      allow(blob).to receive(:properties).and_return({:content_length => 1024})
    end

    it "gets the size of the blob" do
      expect(
        blob_manager.get_blob_size_in_bytes(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
      ).to eq(1024)
    end
  end  

  describe "#create_page_blob" do
    let(:metadata) {
      {
        'property' => 'fake-metadata',
      }
    }
    let(:options) {
      {
        :request_id => request_id,
        :timeout => 120,
        :metadata => metadata
      }
    }

    before do
      @file_path = "/tmp/fake_image"
      File.open(@file_path, 'wb') { |f| f.write("Hello CloudFoundry!") }
    end
    after do
      File.delete(@file_path) if File.exist?(@file_path)
    end

    context "when uploading page blob succeeds" do
      before do
        allow(blob_service).to receive(:put_blob_pages)
        allow(blob_service).to receive(:delete_blob)
      end

      it "raise no error" do
        expect(blob_service).to receive(:create_page_blob).
          with(container_name, blob_name, kind_of(Numeric), options)

        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
        }.not_to raise_error
      end
    end

    context "when uploading page blob fails" do
      before do
        allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name, metadata)
        }.to raise_error /Failed to upload page blob/
      end
    end
  end  

  describe "#create_empty_page_blob" do
    let(:metadata) {
      {
        'property' => 'fake-metadata',
      }
    }
    let(:options) {
      {
        :request_id => request_id,
        :timeout => 120,
        :metadata => metadata
      }
    }

    context "when create empty page blob succeeds" do
      it "raise no error" do
        expect(blob_service).to receive(:create_page_blob).
          with(container_name, blob_name, 1024, options)

        expect {
          blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
        }.not_to raise_error
      end
    end

    context "when create empty page blob fails" do
      before do
        allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.create_empty_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1, metadata)
        }.to raise_error /Failed to create empty page blob/
      end
    end
  end  

  describe "#create_empty_vhd_blob" do
    context "when creating empty vhd blob succeeds" do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:put_blob_pages)
      end

      it "raise no error" do
        expect {
          blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)    
        }.not_to raise_error
      end
    end

    context "when creating empty vhd blob fails" do
      context "blob is not created" do
        before do
          allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
        end

        it "should raise an error and do not delete blob" do
          expect(blob_service).not_to receive(:delete_blob)

          expect {
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)    
          }.to raise_error /Failed to create empty vhd blob/
        end
      end

      context "blob is created" do
        before do
          allow(blob_service).to receive(:create_page_blob)
          allow(blob_service).to receive(:put_blob_pages).and_raise(StandardError)
        end

        it "should raise an error and delete blob" do
          expect(blob_service).to receive(:delete_blob)

          expect {
            blob_manager.create_empty_vhd_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, 1)
          }.to raise_error /Failed to create empty vhd blob/
        end
      end
    end
  end  

  describe "#get_blob_properties" do
    context "when blob exists" do
      let(:blob) { instance_double(Azure::Storage::Blob::Blob) }
      let(:properties) { { "foo" => "bar" } }

      before do
        allow(blob).to receive(:properties).and_return(properties)
      end

      it "should get the properties of the blob" do
        expect(blob_service).to receive(:get_blob_properties).
          with(container_name, blob_name, options).
          and_return(blob)

        expect(
          blob_manager.get_blob_properties(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(properties)
      end
    end

    context "when blob does not exist" do
      before do
        allow(blob_service).to receive(:get_blob_properties).
          and_raise("(404)")
      end

      it "should return nil" do
        expect(
          blob_manager.get_blob_properties(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(nil)
      end
    end
  end

  describe "#get_blob_metadata" do
    context "when blob exists" do
      let(:blob) { instance_double(Azure::Storage::Blob::Blob) }
      let(:metadata) { { 'os_type' => 'fake-os-type' } }

      before do
        allow(blob).to receive(:metadata).and_return(metadata)
      end

      it "should get metadata of the blob" do
        expect(blob_service).to receive(:get_blob_metadata).
          with(container_name, blob_name, options).
          and_return(blob)
        expect(
          blob_manager.get_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to eq(metadata)
      end
    end

    context "when blob does not exist" do
      before do
        allow(blob_service).to receive(:get_blob_metadata).
          and_raise("(404)")
      end

      it "should return nil" do
        expect(
          blob_manager.get_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
        ).to be(nil)
      end
    end
  end

  describe "#set_blob_metadata" do
    let(:metadata) {
      {
        'os_type' => 'fake-os-type',
        'integer' => 1024,
        'boolean' => true
      }
    }
    let(:encoded_metadata) {
      {
        'os_type' => 'fake-os-type',
        'integer' => '1024',
        'boolean' => 'true'
      }
    }

    it "should get metadata of the blob" do
      expect(blob_service).to receive(:set_blob_metadata).
        with(container_name, blob_name, encoded_metadata, options)

      expect {
        blob_manager.set_blob_metadata(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
      }.not_to raise_error
    end
  end

  describe "#list_blobs" do
    context "when the container does not exist" do
      before do
        allow(blob_service).to receive(:list_blobs).and_return('The container does not exist')
      end

      it "should return empty" do
        expect {
          blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        }.to raise_error /The container does not exist/
      end
    end

    context "when the container is empty" do
      let(:tmp_blobs) { Azure::Service::EnumerationResults.new }

      before do
        allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
      end

      it "should return empty" do
        expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)).to be_empty
      end
    end

    context "when the container is not empty" do
      context "without continuation_token" do
        let(:tmp_blobs) { 
          Azure::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        }

        before do
          allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
        end

        it "should return blobs" do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(1)
        end
      end

      context "with continuation_token" do
        let(:tmp_blobs_1) {
          Azure::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        }
        let(:tmp_blobs_2) {
          Azure::Service::EnumerationResults.new(
            [
              'fake-blob'
            ]
          )
        }
        let(:continuation_token) { 'fake-token' }

        before do
          allow(blob_service).to receive(:list_blobs).
            with(container_name, options).and_return(tmp_blobs_1)
          allow(tmp_blobs_1).to receive(:continuation_token).and_return(continuation_token)
          allow(blob_service).to receive(:list_blobs).
            with(container_name, {:marker => continuation_token, :request_id => request_id}).
            and_return(tmp_blobs_2)
        end

        it "should return blobs" do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(2)
        end
      end
    end

  end  

  describe "#snapshot_blob" do
    it "snapshots the blob" do
      snapshot_time = 10
      metadata = {}

      expect(blob_service).to receive(:create_blob_snapshot).
        with(container_name, blob_name, {
          :metadata => metadata,
          :request_id => request_id
        }).
        and_return(snapshot_time)

      expect(
        blob_manager.snapshot_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, metadata)
      ).to eq(snapshot_time)
    end
  end

  describe "#copy_blob" do
    let(:another_storage_account_name) { "another-storage-account-name" }
    let(:source_blob_uri) { "fake-source-blob-uri" }
    let(:another_storage_account) {
      {
        :id => "foo",
        :name => another_storage_account_name,
        :location => "bar",
        :provisioning_state => "bar",
        :account_type => "foo",
        :storage_blob_host => "fake-blob-endpoint",
        :storage_table_host => "fake-table-endpoint"
      }
    }
    let(:blob) { instance_double(Azure::Storage::Blob::Blob) }
    before do
      allow(azure_client2).to receive(:get_storage_account_by_name).
        with(another_storage_account_name).
        and_return(another_storage_account)
      allow(blob_service).to receive(:get_blob_properties).and_return(blob)
    end

    context "when everything is fine" do
      context "when copy status is success in the first response" do
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'success'])
        end

        it "succeeds to copy the blob" do
          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.not_to raise_error
        end
      end

      context "when copy status is success in the fourth response" do
        let(:first_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "pending",
            :copy_status_description => "fake-status-description",
            :copy_progress => "1234/5678"
          }
        }
        let(:second_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "pending",
            :copy_status_description => "fake-status-description",
            :copy_progress => "3456/5678"
          }
        }
        let(:third_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "pending",
            :copy_status_description => "fake-status-description",
            :copy_progress => "5666/5678"
          }
        }
        let(:fourth_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "success",
            :copy_status_description => "fake-status-description",
            :copy_progress => "5678/5678"
          }
        }
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).
            and_return(first_blob_properties, second_blob_properties, third_blob_properties, fourth_blob_properties)
        end

        it "succeeds to copy the blob" do
          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.not_to raise_error
        end
      end
    end

    context "when copy status is failed" do
      context "when copy_blob_from_uri returns failed" do
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'failed'])
        end

        it "fails to copy the blob" do
          expect(blob_service).to receive(:delete_blob).with(container_name, blob_name, options)

          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.to raise_error /Failed to copy the blob/
        end
      end

      context "when copy status is failed in the second response" do
        let(:first_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "pending",
            :copy_status_description => "fake-status-description",
            :copy_progress => "1234/5678"
          }
        }
        let(:second_blob_properties) {
          {
            :copy_id => "fake-copy-id",
            :copy_status => "failed",
            :copy_status_description => "fake-status-description"
          }
        }
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).
            and_return(first_blob_properties, second_blob_properties)
        end

        it "fails to copy the blob" do
          expect(blob_service).to receive(:delete_blob).with(container_name, blob_name, options)

          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.to raise_error /Failed to copy the blob/
        end
      end
    end

    context "when the progress of copying is interrupted" do
      context "when copy id is nil" do
        let(:blob_properties) {
          {
            # copy_id is nil
            :copy_status => "interrupted"
          }
        }
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).and_return(blob_properties)
        end

        it "should raise an error" do
          expect(blob_service).to receive(:delete_blob).
            with(container_name, blob_name, options)

          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.to raise_error /The progress of copying the blob #{source_blob_uri} to #{container_name}\/#{blob_name} was interrupted/
        end
      end

      context "when copy id does not match" do
        let(:blob_properties) {
          {
            :copy_id => "another-copy-id",
            :copy_status => "pending",
            :copy_status_description => "fake-status-description",
            :copy_progress => "1234/5678"
          }
        }
        before do
          allow(blob_service).to receive(:copy_blob_from_uri).and_return(['fake-copy-id', 'pending'])
          allow(blob).to receive(:properties).and_return(blob_properties)
        end

        it "should raise an error" do
          expect(blob_service).to receive(:delete_blob).
            with(container_name, blob_name, options)

          expect {
            blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
          }.to raise_error /The progress of copying the blob #{source_blob_uri} to #{container_name}\/#{blob_name} was interrupted/
        end
      end
    end
  end

  describe "#has_container?" do
    context "when the container exists" do
      let(:container) { instance_double(Azure::Storage::Blob::Container::Container) }
      let(:container_properties) { "fake-properties" }

      before do
        allow(blob_service).to receive(:get_container_properties).
          with(container_name, options).and_return(container)
        allow(container).to receive(:properties).and_return(container_properties)
      end

      it "should return true" do
        expect(
          blob_manager.has_container?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        ).to be(true)
      end
    end

    context "when the container does not exist" do
      before do
        allow(blob_service).to receive(:get_container_properties).
          and_raise("Error code: (404). This is a test!")
      end

      it "should return false" do
        expect(
          blob_manager.has_container?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        ).to be(false)
      end
    end

    context "when the server returns an error" do
      before do
        allow(blob_service).to receive(:get_container_properties).
          and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.has_container?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        }.to raise_error /has_container/
      end
    end
  end

  describe "#prepare" do
    let(:another_storage_account_name) { "another-storage-account-name" }
    let(:another_storage_account) {
      {
        :id => "foo",
        :name => another_storage_account_name,
        :location => "bar",
        :provisioning_state => "bar",
        :account_type => "foo",
        :storage_blob_host => "fake-blob-endpoint",
        :storage_table_host => "fake-table-endpoint"
      }
    }

    before do
      allow(azure_client2).to receive(:get_storage_account_by_name).
        with(another_storage_account_name).
        and_return(another_storage_account)
    end

    context "when the storage account is default storage account" do
      it "creates the container, and set the acl" do
        expect(blob_service).to receive(:create_container).
          with(container_name, options).
          and_return(true)
        expect(blob_service).to receive(:set_container_acl).with('stemcell', 'blob', options)

        expect {
          blob_manager.prepare(another_storage_account_name, containers: [container_name], is_default_storage_account: true)
        }.not_to raise_error
      end
    end

    context "when the storage account is not default storage account" do
      it "creates the container, and doesn't set the acl" do
        expect(blob_service).to receive(:create_container).
          with(container_name, options).
          and_return(true)
        expect(blob_service).not_to receive(:set_container_acl)

        expect {
          blob_manager.prepare(another_storage_account_name, containers: [container_name])
        }.not_to raise_error
      end
    end
  end
end

describe Bosh::AzureCloud::CustomizedRetryPolicyFilter do
  let(:customized_retry_policy_filter) { Bosh::AzureCloud::CustomizedRetryPolicyFilter.new }
  describe "#apply_retry_policy" do
    context "when there is no error" do
      let(:retry_data) { {} }

      it "should not set the retryable" do
        customized_retry_policy_filter.apply_retry_policy(retry_data)
        expect(retry_data[:retryable]).to be(nil)
      end
    end

    context "when the error is neither OpenSSL::SSL::SSLError nor OpenSSL::X509::StoreError" do
      let(:retry_data) {
        {
          :error => StandardError
        }
      }

      it "should not set the retryable" do
        customized_retry_policy_filter.apply_retry_policy(retry_data)
        expect(retry_data[:retryable]).to be(nil)
      end
    end

    context "when the error is OpenSSL::SSL::SSLError" do
      context "when the error message is related to connection reset" do
        let(:retry_data) {
          {
            :error => OpenSSL::SSL::SSLError.new("Connection reset by peer - SSL_connect")
          }
        }

        it "should set the retryable to true" do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(true)
        end
      end

      context "when the error message is not related to connection reset" do
        let(:retry_data) {
          {
            :error => OpenSSL::SSL::SSLError.new("Some other error")
          }
        }

        it "should not set the retryable" do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(nil)
        end
      end
    end

    context "when the error is OpenSSL::X509::StoreError" do
      context "when the error message is related to connection reset" do
        let(:retry_data) {
          {
            :error => OpenSSL::X509::StoreError.new("Connection reset by peer - SSL_connect")
          }
        }

        it "should set the retryable to true" do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(true)
        end
      end

      context "when the error message is not related to connection reset" do
        let(:retry_data) {
          {
            :error => OpenSSL::X509::StoreError.new("Some other error")
          }
        }

        it "should not set the retryable" do
          customized_retry_policy_filter.apply_retry_policy(retry_data)
          expect(retry_data[:retryable]).to be(nil)
        end
      end
    end
  end
end
