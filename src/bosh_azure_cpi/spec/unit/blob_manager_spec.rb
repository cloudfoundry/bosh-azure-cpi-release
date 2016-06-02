require 'spec_helper'

describe Bosh::AzureCloud::BlobManager do
  let(:azure_properties) { mock_azure_properties }
  let(:azure_client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:blob_manager) { Bosh::AzureCloud::BlobManager.new(azure_properties, azure_client2) }

  let(:container_name) { "fake-container-name" }
  let(:blob_name) { "fake-blob-name" }
  let(:keys) { ["fake-key-1", "fake-key-2"] }

  let(:azure_client) { instance_double(Azure::Client) }
  let(:blob_service) { instance_double(Azure::Blob::BlobService) }
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

  before do
    allow(Bosh::AzureCloud::AzureClient2).to receive(:new).
      and_return(azure_client2)
    allow(azure_client2).to receive(:get_storage_account_keys_by_name).
      and_return(keys)
    allow(azure_client2).to receive(:get_storage_account_by_name).
      with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).
      and_return(storage_account)
    allow(azure_client).to receive(:storage_blob_host=)
    allow(azure_client).to receive(:storage_blob_host).and_return(blob_host)
    allow(azure_client).to receive(:blobs).
      and_return(blob_service)
    allow(Azure).to receive(:client).
      with(storage_account_name: MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, storage_access_key: keys[0]).
      and_return(azure_client)
  end

  describe "#delete_blob" do
    it "delete the blob" do
      expect(blob_service).to receive(:delete_blob).
        with(container_name, blob_name, {
          :delete_snapshots => :include
        })

      blob_manager.delete_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name)
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
          :snapshot => snapshot_time
        })

      blob_manager.delete_blob_snapshot(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, blob_name, snapshot_time)
    end
  end  

  describe "#create_page_blob" do
    before do
      @file_path = "/tmp/fake_image"
      File.open(@file_path, 'wb') { |f| f.write("Hello CloudFoundry!") }
    end
    after do
      File.delete(@file_path) if File.exist?(@file_path)
    end

    context "when uploading page blob succeeds" do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:create_blob_pages)
        allow(blob_service).to receive(:delete_blob)
      end

      it "raise no error" do
        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name) 
        }.not_to raise_error
      end
    end

    context "when uploading page blob fails" do
      before do
        allow(blob_service).to receive(:create_page_blob).and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.create_page_blob(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, @file_path, blob_name) 
        }.to raise_error /Failed to upload page blob/
      end
    end
  end  

  describe "#create_empty_vhd_blob" do
    context "when creating empty vhd blob succeeds" do
      before do
        allow(blob_service).to receive(:create_page_blob)
        allow(blob_service).to receive(:create_blob_pages)
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
          allow(blob_service).to receive(:create_blob_pages).and_raise(StandardError)
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

  describe "#list_blobs" do
    class MyArray < Array
      attr_accessor :continuation_token
    end

    context "when the container is empty" do
      tmp_blobs = MyArray.new
      before do
        allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
      end

      it "returns empty blobs" do
        expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)).to be_empty
      end
    end

    context "when the container is not empty" do
      context "when blob service client returns no continuation_token" do
        tmp_blobs = MyArray.new
        tmp_blobs << "first blob"
        before do
          allow(blob_service).to receive(:list_blobs).and_return(tmp_blobs)
        end

        it "returns blobs" do
          expect(blob_manager.list_blobs(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name).size).to eq(1)
        end
      end

      context "when blob service client returns continuation_token" do
        tmp1 = MyArray.new
        tmp1 << "first blob"
        tmp1.continuation_token = "fake token"
        tmp2 = MyArray.new
        tmp2 << "second blob"
        before do
          allow(blob_service).to receive(:list_blobs).
            with(container_name, {}).and_return(tmp1)
          allow(blob_service).to receive(:list_blobs).
            with(container_name, {:marker => "fake token"}).and_return(tmp2)
        end

        it "returns blobs" do
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
          :metadata => metadata
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
    before do
      allow(Azure).to receive(:client).
        with(storage_account_name: another_storage_account_name, storage_access_key: keys[0]).
        and_return(azure_client)
      allow(blob_service).to receive(:service_properties_headers).and_return({})
      allow(blob_service).to receive(:generate_uri).and_return("fake-uri")
      allow(azure_client2).to receive(:get_storage_account_by_name).
        with(another_storage_account_name).
        and_return(another_storage_account)
    end

    class Response
      attr_accessor :headers
      def initialize
        @headers = {}
      end
    end

    context "when copy status is success" do
      before do
        response = Response.new
        response.headers["x-ms-copy-id"] = "copy-id-1"
        response.headers["x-ms-copy-status"] = "success"
        allow(blob_service).to receive(:call).and_return(response)
      end

      it "succeeds to copy the blob" do
        expect {
          blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
        }.not_to raise_error
      end
    end

    context "when copy status is not success or pending" do
      before do
        response = Response.new
        response.headers["x-ms-copy-id"] = "copy-id-1"
        response.headers["x-ms-copy-status"] = "failed"
        allow(blob_service).to receive(:call).and_return(response)
      end

      it "fails to copy the blob" do
        expect(blob_service).to receive(:delete_blob).
          with(container_name, blob_name)

        expect {
          blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
        }.to raise_error /Failed to copy the blob/
      end
    end

    context "when the progress of copying is interrupted" do
      class MyBlob
        attr_accessor :properties
        def initialize
          @properties = {}
        end
      end

      before do
        response = Response.new
        response.headers["x-ms-copy-id"] = "copy-id-1"
        response.headers["x-ms-copy-status"] = "pending"
        allow(blob_service).to receive(:call).and_return(response)
        blob = MyBlob.new
        blob.properties = { :copy_id => "copy-id-2" }
        allow(blob_service).to receive(:get_blob_properties).and_return(blob)
      end

      it "should raise an error" do
        expect(blob_service).to receive(:delete_blob).
          with(container_name, blob_name)

        expect {
          blob_manager.copy_blob(another_storage_account_name, container_name, blob_name, source_blob_uri)
        }.to raise_error /The progress of copying the blob #{source_blob_uri} to #{container_name}\/#{blob_name} was interrupted/
      end
    end
  end

  describe "#create_container" do
    let(:options) { {} }

    context "when creating container succeeds" do
      context "the container does not exist" do
        before do
          allow(blob_service).to receive(:create_container).
            with(container_name, options)
        end

        it "should return true" do
          expect(
            blob_manager.create_container(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, options)
          ).to be(true)
        end
      end

      context "the container exists" do
        before do
          allow(blob_service).to receive(:create_container).
            with(container_name, options).
            and_raise("(409)")
        end

        it "should return true" do
          expect(
            blob_manager.create_container(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, options)
          ).to be(true)
        end
      end
    end

    context "when the status code is not 409" do
      before do
        allow(blob_service).to receive(:create_container).and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.create_container(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name, options)
        }.to raise_error /Failed to create container/
      end
    end
  end

  describe "#has_container?" do
    context "when the container exists" do
      before do
        allow(blob_service).to receive(:get_container_properties).
          with(container_name)
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
          with(container_name).
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
          with(container_name).
          and_raise(StandardError)
      end

      it "should raise an error" do
        expect {
          blob_manager.has_container?(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, container_name)
        }.to raise_error /has_container/
      end
    end
  end
end
