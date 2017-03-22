require 'spec_helper'

describe Bosh::AzureCloud::LightStemcellManager do
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:azure_client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:light_stemcell_manager) { Bosh::AzureCloud::LightStemcellManager.new(blob_manager, storage_account_manager, azure_client2) }

  let(:stemcell_container) { 'stemcell' }
  let(:stemcell_name) { "fake-stemcell-name" }
  let(:location) { 'fake-location' }
  let(:version) { "fake-version" }
  let(:storage_account) {
    {
      :id => "foo",
      :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
      :location => location,
      :provisioning_state => "bar",
      :account_type => "foo",
      :storage_blob_host => "fake-blob-endpoint",
      :storage_table_host => "fake-table-endpoint"
    }
  }

  before do
    allow(storage_account_manager).to receive(:default_storage_account).
      and_return(storage_account)
  end

  describe "#delete_stemcell" do
    context "when the stemcell exists" do
      let(:metadata) { { "foo" => "bar" } }

      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
          and_return(metadata)
      end

      it "should delete the stemcell" do
        expect(blob_manager).to receive(:delete_blob)

        light_stemcell_manager.delete_stemcell(stemcell_name)
      end
    end

    context "when the stemcell does not exist" do
      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          and_return(nil)
      end

      it "should do nothing" do
        expect(blob_manager).not_to receive(:delete_blob)

        light_stemcell_manager.delete_stemcell(stemcell_name)
      end
    end
  end  

  describe "#create_stemcell" do
    let(:stemcell_properties) {
      {
        "name" => "fake-name",
        "version" => version,
        "infrastructure" => "azure",
        "hypervisor" => "hyperv",
        "disk" => "3072",
        "disk_format" => "vhd",
        "container_format" => "bare",
        "os_type" => "linux",
        "os_distro" => "ubuntu",
        "architecture" => "x86_64",
        "image" => {
          "publisher" => "bosh",
          "offer" => "UbuntuServer",
          "sku" => "trusty",
          "version" => version
        }
      }
    }

    context "when the platform image exists" do
      let(:versions) {
        [
          {
            :id       => 'a',
            :name     => version,
            :location => location
          }, {
            :id       => 'c',
            :name     => 'd',
            :location => location
          }
        ]
      }

      before do
        allow(azure_client2).to receive(:list_platform_image_versions).
            and_return(versions)
        allow(blob_manager).to receive(:create_empty_page_blob).
          and_return(true)
      end

      it "should create the stemcell" do
        expect(azure_client2).to receive(:list_platform_image_versions)
        expect(blob_manager).to receive(:create_empty_page_blob)

        expect(light_stemcell_manager.create_stemcell(stemcell_properties)).to start_with('bosh-light-stemcell')
      end
    end

    context "when the platform image does not exist" do
      let(:versions) {
        [
          {
            :id       => 'a',
            :name     => 'b',
            :location => location
          }, {
            :id       => 'c',
            :name     => 'd',
            :location => location
          }
        ]
      }

      before do
        allow(azure_client2).to receive(:list_platform_image_versions).
            and_return(versions)
      end

      it "should raise an error" do
        expect(azure_client2).to receive(:list_platform_image_versions)
        expect(blob_manager).not_to receive(:create_empty_page_blob)

        expect {
          light_stemcell_manager.create_stemcell(stemcell_properties)
        }.to raise_error /Cannot find the light stemcell/
      end
    end
  end  

  describe "#has_stemcell?" do
    context "when the blob does not exist in the default storage account" do
      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          and_return(nil)
      end

      it "should return false" do
        expect(blob_manager).to receive(:get_blob_metadata)

        expect(
          light_stemcell_manager.has_stemcell?(location, stemcell_name)
        ).to be(false)
      end
    end

    context "when the blob exists in the default storage account" do
      let(:metadata) {
        {
          "name" => "fake-name",
          "version" => version,
          "infrastructure" => "azure",
          "hypervisor" => "hyperv",
          "disk" => "3072",
          "disk_format" => "vhd",
          "container_format" => "bare",
          "os_type" => "linux",
          "os_distro" => "ubuntu",
          "architecture" => "x86_64",
          "image" => "{\"publisher\"=>\"bosh\", \"offer\"=>\"UbuntuServer\", \"sku\"=>\"trusty\", \"version\"=>\"#{version}\"}"
        }
      }

      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
          and_return(metadata)
      end

      context "but the platform image does not exist" do
        before do
          allow(azure_client2).to receive(:list_platform_image_versions).
            and_return([])
        end

        it "should return false" do
          expect(blob_manager).to receive(:get_blob_metadata)
          expect(azure_client2).to receive(:list_platform_image_versions)

          expect(
            light_stemcell_manager.has_stemcell?(location, stemcell_name)
          ).to be(false)
        end
      end

      context "and the platform image exists" do
        let(:versions) {
          [
            {
              :id       => 'a',
              :name     => version,
              :location => location
            }, {
              :id       => 'c',
              :name     => 'd',
              :location => location
            }
          ]
        }

        before do
          allow(azure_client2).to receive(:list_platform_image_versions).
            and_return(versions)
        end

        it "should return true" do
          expect(blob_manager).to receive(:get_blob_metadata)
          expect(azure_client2).to receive(:list_platform_image_versions)

          expect(
            light_stemcell_manager.has_stemcell?(location, stemcell_name)
          ).to be(true)
        end
      end
    end
  end

  describe "#get_stemcell_info" do
    context "when the blob does not exist in the default storage account" do
      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
          and_return(nil)
      end

      it "should throw an error" do
        expect {
          light_stemcell_manager.get_stemcell_info(stemcell_name)
        }.to raise_error /The light stemcell `#{stemcell_name}' does not exist in the storage account `#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}'/
      end
    end

    context "when the blob exists in the default storage account" do
      let(:metadata) { { "foo" => "bar" } }

      before do
        allow(blob_manager).to receive(:get_blob_metadata).
          with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, stemcell_container, "#{stemcell_name}.vhd").
          and_return(metadata)
      end

      it "should return stemcell info" do
        stemcell_info = light_stemcell_manager.get_stemcell_info(stemcell_name)
        expect(stemcell_info.uri).to eq('')
        expect(stemcell_info.metadata).to eq(metadata)
      end
    end
  end
end
