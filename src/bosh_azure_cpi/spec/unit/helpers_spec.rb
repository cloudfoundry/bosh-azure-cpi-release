require "spec_helper"

describe Bosh::AzureCloud::Helpers do
  class HelpersTester
    include Bosh::AzureCloud::Helpers
  end

  helpers_tester = HelpersTester.new

  describe "#encode_metadata" do
    let(:metadata) do
      {
        "user-agent" => "bosh",
        "foo"        => 1,
        "bar"        => true
      }
    end

    it "should return an encoded metadata" do
      expect(helpers_tester.encode_metadata(metadata)).to include(
        "user-agent" => "bosh",
        "foo"        => "1",
        "bar"        => "true"
      )
    end
  end

  describe "#get_storage_account_name_from_instance_id" do
    context "when instance id is valid" do
      let(:storage_account_name) { "foostorageaccount" }
      let(:instance_id) { "#{storage_account_name}-12345688-1234" }

      it "should return the storage account name" do
        expect(
          helpers_tester.get_storage_account_name_from_instance_id(instance_id)
        ).to eq(storage_account_name)
      end
    end

    context "when instance id is invalid" do
      let(:storage_account_name) { "foostorageaccount" }
      let(:instance_id) { "#{storage_account_name}123456881234" }

      it "should raise an error" do
        expect {
          helpers_tester.get_storage_account_name_from_instance_id(instance_id)
        }.to raise_error /Invalid instance id/
      end
    end
  end

  describe "#validate_disk_caching" do
    context "when disk caching is invalid" do
      let(:caching) { "Invalid" }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_caching(caching)
        }.to raise_error /Unknown disk caching/
      end
    end
  end

  describe "#get_arm_endpoint" do
    context "when environment is Azure" do
      let(:azure_properties) { {'environment' => 'AzureCloud'} }

      it "should return Azure ARM endpoint" do
        expect(
          helpers_tester.get_arm_endpoint(azure_properties)
        ).to eq("https://management.azure.com/")
      end
    end

    context "when environment is AzureChinaCloud" do
      let(:azure_properties) { {'environment' => 'AzureChinaCloud'} }

      it "should return AzureChinaCloud ARM endpoint" do
        expect(
          helpers_tester.get_arm_endpoint(azure_properties)
        ).to eq("https://management.chinacloudapi.cn/")
      end
    end

    context "when environment is AzureStack" do
      context "when azure_stack_domain is not provided" do
        let(:azure_properties) {
          {
            'environment'                => 'AzureStack',
            'azure_stack_authentication' => 'fake-authentication'
          }
        }

        it "should return an error" do
          expect {
            helpers_tester.get_arm_endpoint(azure_properties)
          }.to raise_error /missing configuration parameters for AzureStack/
        end
      end

      context "when azure_stack_authentication is not provided" do
        let(:azure_properties) {
          {
            'environment'                => 'AzureStack',
            'azure_stack_domain'         => 'fake-domain'
          }
        }

        it "should return an error" do
          expect {
            helpers_tester.get_arm_endpoint(azure_properties)
          }.to raise_error /missing configuration parameters for AzureStack/
        end
      end

      context "when all required parameters are provided" do
        let(:azure_properties) {
          {
            'environment'                => 'AzureStack',
            'azure_stack_domain'         => 'fake-domain',
            'azure_stack_authentication' => 'fake-authentication'
          }
        }

        it "should return AzureStack ARM endpoint" do
          expect(
            helpers_tester.get_arm_endpoint(azure_properties)
          ).to eq("https://api.fake-domain")
        end
      end
    end
  end

  describe "#get_token_resource" do
    context "when environment is Azure" do
      let(:azure_properties) { {'environment' => 'AzureCloud'} }

      it "should return Azure resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://management.azure.com/")
      end
    end

    context "when environment is AzureChinaCloud" do
      let(:azure_properties) { {'environment' => 'AzureChinaCloud'} }

      it "should return AzureChinaCloud resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://management.chinacloudapi.cn/")
      end
    end

    context "when environment is AzureStack" do
      let(:azure_properties) {
        {
          'environment'                => 'AzureStack',
          'azure_stack_domain'         => 'fake-domain',
          'azure_stack_authentication' => 'fake-authentication'
        }
      }

      it "should return AzureStack resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://azurestack.local-api/")
      end
    end
  end

  describe "#get_azure_authentication_endpoint_and_api_version" do
    context "when environment is Azure" do
      let(:azure_properties) {
        {
          'environment' => 'AzureCloud',
          'tenant_id'   => 'fake-tenant-id'
        }
      }

      it "should return Azure authentication endpoint and api version" do
        expect(
          helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
        ).to eq(["https://login.microsoftonline.com/fake-tenant-id/oauth2/token", "2015-05-01-preview"])
      end
    end

    context "when environment is AzureChinaCloud" do
      let(:azure_properties) {
        {
          'environment' => 'AzureChinaCloud',
          'tenant_id'   => 'fake-tenant-id'
        }
      }

      it "should return AzureChinaCloud authentication endpoint and api version" do
        expect(
          helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
        ).to eq(["https://login.chinacloudapi.cn/fake-tenant-id/oauth2/token", "2015-06-15"])
      end
    end

    context "when environment is AzureStack" do
      context "when azure_stack_domain is not provided" do
        let(:azure_properties) {
          {
            'environment'                => 'AzureStack',
            'azure_stack_authentication' => 'fake-authentication'
          }
        }

        it "should return an error" do
          expect {
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          }.to raise_error /missing configuration parameters for AzureStack/
        end
      end

      context "when azure_stack_authentication is not provided" do
        let(:azure_properties) {
          {
            'environment'                => 'AzureStack',
            'azure_stack_domain'         => 'fake-domain'
          }
        }

        it "should return an error" do
          expect {
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          }.to raise_error /missing configuration parameters for AzureStack/
        end
      end

      context "when all required parameters are provided" do
        context "when azure_stack_authentication is AzureStack" do
          let(:azure_properties) {
            {
              'environment'                => 'AzureStack',
              'azure_stack_domain'         => 'fake-domain',
              'azure_stack_authentication' => 'AzureStack',
              'tenant_id'                  => 'fake-tenant-id'
            }
          }

          it "should return AzureStack authentication endpoint and api version" do
            expect(
              helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
            ).to eq(["https://fake-domain/oauth2/token", "2015-05-01-preview"])
          end
        end

        context "when azure_stack_authentication is AzureStackAD" do
          let(:azure_properties) {
            {
              'environment'                => 'AzureStack',
              'azure_stack_domain'         => 'fake-domain',
              'azure_stack_authentication' => 'AzureStackAD',
              'tenant_id'                  => 'fake-tenant-id'
            }
          }

          it "should return AzureStack authentication endpoint and api version" do
            expect(
              helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
            ).to eq(["https://fake-domain/fake-tenant-id/oauth2/token", "2015-05-01-preview"])
          end
        end

        context "when azure_stack_authentication is AzureAD" do
          let(:azure_properties) {
            {
              'environment'                => 'AzureStack',
              'azure_stack_domain'         => 'fake-domain',
              'azure_stack_authentication' => 'AzureAD',
              'tenant_id'                  => 'fake-tenant-id'
            }
          }

          it "should return Azure authentication endpoint and api version" do
            expect(
              helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
            ).to eq(["https://login.microsoftonline.com/fake-tenant-id/oauth2/token", "2015-05-01-preview"])
          end
        end
      end
    end
  end

  describe "#initialize_azure_storage_client" do
    let(:azure_client2) { instance_double('Bosh::AzureCloud::AzureClient2') }
    let(:azure_client) { instance_double(Azure::Client) }
    let(:storage_account_name) { "fake-storage-account-name" }
    let(:storage_access_key) { "fake-storage-access-key" }
    let(:storage_account) {
      {
        :name => storage_account_name,
        :key => storage_access_key,
        :storage_blob_host => 'fake-blob-host/',
        :storage_table_host => 'fake-table-host/',
      }
    }
    let(:blob_host) { "fake-blob-host" }
    let(:table_host) { "fake-table-host" }

    before do
      allow(Azure).to receive(:new).
        with(storage_account_name, storage_access_key).
        and_return(azure_client)
      allow(azure_client).to receive(:storage_blob_host=)
      allow(azure_client).to receive(:storage_blob_host).and_return(blob_host)
      allow(azure_client).to receive(:storage_table_host=)
      allow(azure_client).to receive(:storage_table_host).and_return(table_host)
    end

    context "for blob" do
      it "should return an azure storage client with setting storage blob host" do
        client = helpers_tester.initialize_azure_storage_client(storage_account, 'blob')
        expect(
          client.storage_blob_host
        ).to eq(blob_host)
      end
    end

    context "for table" do
      context "when the storage account is standard" do
        it "should return an azure storage client with setting table blob host" do
          client = helpers_tester.initialize_azure_storage_client(storage_account, 'table')
          expect(
            client.storage_table_host
          ).to eq(table_host)
        end
      end

      context "when the storage account is premium" do
        let(:storage_account) {
          {
            :name => storage_account_name,
            :key => storage_access_key,
            :storage_blob_host => 'fake-blob-host/',
          }
        }

        it "should raise an error" do
          expect {
            helpers_tester.initialize_azure_storage_client(storage_account, 'table')
          }.to raise_error "The storage account `#{storage_account_name}' does not support table"
        end
      end
    end

    context "for others" do
      it "should raise an error" do
        expect {
          helpers_tester.initialize_azure_storage_client(storage_account, 'others')
        }.to raise_error "No support for the storage service: `others'"
      end
    end
  end

  describe "#validate_disk_size" do
    context "disk size is not an integer" do
      let(:disk_size) { "fake-size" }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_size(disk_size)
        }.to raise_error "disk size needs to be an integer"
      end
    end

    context "disk size is smaller than 1 GiB" do
      let(:disk_size) { 666 }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_size(disk_size)
        }.to raise_error "Azure CPI minimum disk size is 1 GiB"
      end
    end

    context "disk size is larger than 1s TiB" do
      let(:disk_size) { 6666 * 1024 }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_size(disk_size)
        }.to raise_error "Azure CPI maximum disk size is 1 TiB"
      end
    end
  end
end
