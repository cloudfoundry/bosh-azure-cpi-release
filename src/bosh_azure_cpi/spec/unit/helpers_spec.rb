require "spec_helper"

describe Bosh::AzureCloud::Helpers do
  let(:api_version) { AZURE_API_VERSION }
  let(:azure_stack_api_version) { AZURE_STACK_API_VERSION }
  let(:azure_china_api_version) { AZURE_CHINA_API_VERSION }
  let(:azure_usgov_api_version) { AZURE_USGOV_API_VERSION }
  let(:azure_german_api_version) { AZURE_GERMAN_API_VERSION }

  class HelpersTester
    include Bosh::AzureCloud::Helpers

    def initialize
      @logger = Logger.new('/dev/null')
    end

    def set_logger(logger)
      @logger = logger
    end
  end

  helpers_tester = HelpersTester.new

  describe "#cloud_error" do
    let(:message) { "fake-error-message" }

    after do
      helpers_tester.set_logger(Logger.new('/dev/null'))
    end

    context "when logger is not nil" do
      let(:logger_strio) { StringIO.new }
      before do
        helpers_tester.set_logger(Logger.new(logger_strio))
      end

      context "when exception is nil" do
        it "should raise CloudError and log the message" do
          expect {
            helpers_tester.cloud_error(message)
          }.to raise_error(Bosh::Clouds::CloudError, message)
          expect(logger_strio.string).to include(message)
        end
      end

      context "when exception is not nil" do
        let(:fake_exception) { StandardError.new('fake-exception') }
        it "should raise CloudError, log the message and the exception" do
          expect {
            helpers_tester.cloud_error(message, fake_exception)
          }.to raise_error(Bosh::Clouds::CloudError, message)
          expect(logger_strio.string).to include(message)
          expect(logger_strio.string).to include("fake-exception")
        end
      end
    end

    context "when logger is nil" do
      before do
        helpers_tester.set_logger(nil)
      end

      it "should raise CloudError" do
        expect {
          helpers_tester.cloud_error(message)
        }.to raise_error(Bosh::Clouds::CloudError, message)
      end
    end
  end

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

    context "when environment is AzureUSGovernment" do
      let(:azure_properties) { {'environment' => 'AzureUSGovernment'} }

      it "should return AzureUSGovernment ARM endpoint" do
        expect(
          helpers_tester.get_arm_endpoint(azure_properties)
        ).to eq("https://management.usgovcloudapi.net/")
      end
    end

    context "when environment is AzureStack" do
      let(:azure_properties) {
        {
          'environment' => 'AzureStack',
          'azure_stack' => {
            'domain'          => 'fake-domain',
            'authentication'  => 'fake-authentication',
            'endpoint_prefix' => 'api'
          }
        }
      }

      it "should return AzureStack ARM endpoint" do
        expect(
          helpers_tester.get_arm_endpoint(azure_properties)
        ).to eq("https://api.fake-domain")
      end
    end

    context "when environment is AzureGermanCloud" do
      let(:azure_properties) { {'environment' => 'AzureGermanCloud'} }

      it "should return AzureGermanCloud ARM endpoint" do
        expect(
          helpers_tester.get_arm_endpoint(azure_properties)
        ).to eq("https://management.microsoftazure.de/")
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

    context "when environment is AzureUSGovernment" do
      let(:azure_properties) { {'environment' => 'AzureUSGovernment'} }

      it "should return AzureUSGovernment resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://management.usgovcloudapi.net/")
      end
    end

    context "when environment is AzureStack" do
      let(:azure_properties) {
        {
          'environment' => 'AzureStack',
          'azure_stack' => {
             'resource' => 'https://azurestack.local-api/'
          }
        }
      }

      it "should return AzureStack resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://azurestack.local-api/")
      end
    end

    context "when environment is AzureGermanCloud" do
      let(:azure_properties) { {'environment' => 'AzureGermanCloud'} }

      it "should return AzureGermanCloud resource" do
        expect(
          helpers_tester.get_token_resource(azure_properties)
        ).to eq("https://management.microsoftazure.de/")
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
        ).to eq(["https://login.microsoftonline.com/fake-tenant-id/oauth2/token", api_version])
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
        ).to eq(["https://login.chinacloudapi.cn/fake-tenant-id/oauth2/token", azure_china_api_version])
      end
    end

    context "when environment is AzureUSGovernment" do
      let(:azure_properties) {
        {
          'environment' => 'AzureUSGovernment',
          'tenant_id'   => 'fake-tenant-id'
        }
      }

      it "should return AzureUSGovernment authentication endpoint and api version" do
        expect(
          helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
        ).to eq(["https://login.microsoftonline.com/fake-tenant-id/oauth2/token", azure_usgov_api_version])
      end
    end

    context "when environment is AzureStack" do
      let(:azure_properties) {
        {
          'environment' => 'AzureStack',
          'azure_stack' => {
            'domain'          => 'fake-domain',
            'endpoint_prefix' => 'api',
          },
          'tenant_id'   => 'fake-tenant-id'
        }
      }

      context "when azure_stack.authentication is AzureStack" do
        before do
          azure_properties['azure_stack']['authentication'] = 'AzureStack'
        end

        it "should return AzureStack authentication endpoint and api version" do
          expect(
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          ).to eq(["https://fake-domain/oauth2/token", azure_stack_api_version])
        end
      end

      context "when azure_stack.authentication is AzureStackAD" do
        before do
          azure_properties['azure_stack']['authentication'] = 'AzureStackAD'
        end

        it "should return AzureStack authentication endpoint and api version" do
          expect(
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          ).to eq(["https://fake-domain/fake-tenant-id/oauth2/token", azure_stack_api_version])
        end
      end

      context "when azure_stack.authentication is AzureAD" do
        before do
          azure_properties['azure_stack']['authentication'] = 'AzureAD'
        end

        it "should return Azure authentication endpoint and api version" do
          expect(
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          ).to eq(["https://login.microsoftonline.com/fake-tenant-id/oauth2/token", api_version])
        end
      end

      context "when the value of azure_stack.authentication is not supported" do
        before do
          azure_properties['azure_stack']['authentication'] = 'NotSupportedValue'
        end

        it "should raise an error" do
          expect {
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          }.to raise_error(/No support for the AzureStack authentication: `NotSupportedValue'/)
        end
      end
    end

    context "when environment is AzureGermanCloud" do
      let(:azure_properties) {
        {
          'environment' => 'AzureGermanCloud',
          'tenant_id'   => 'fake-tenant-id'
        }
      }

      it "should return AzureGermanCloud authentication endpoint and api version" do
        expect(
          helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
        ).to eq(["https://login.microsoftonline.de/fake-tenant-id/oauth2/token", azure_german_api_version])
      end
    end
  end

  describe "#initialize_azure_storage_client" do
    let(:azure_client2) { instance_double('Bosh::AzureCloud::AzureClient2') }
    let(:azure_client) { instance_double(Azure::Storage::Client) }
    let(:storage_account_name) { "fake-storage-account-name" }
    let(:storage_access_key) { "fake-storage-access-key" }
    let(:storage_account) {
      {
        :name => storage_account_name,
        :key => storage_access_key,
        :storage_blob_host => 'https://fake-blob-host:443/',
        :storage_table_host => 'https://fake-table-host:443/',
      }
    }
    let(:blob_host_https) { "https://fake-blob-host:443" }
    let(:table_host_https) { "https://fake-table-host:443" }
    let(:blob_host_http) { "http://fake-blob-host" }
    let(:table_host_http) { "http://fake-table-host" }

    before do
      allow(Azure::Storage::Client).to receive(:create).
        and_return(azure_client)
      allow(azure_client).to receive(:storage_blob_host=)
      allow(azure_client).to receive(:storage_blob_host).and_return(blob_host_https)
      allow(azure_client).to receive(:storage_table_host=)
      allow(azure_client).to receive(:storage_table_host).and_return(table_host_https)
    end

    context "for blob" do
      context "use https" do
        it "should return an azure storage client with setting storage blob host (https)" do
          client = helpers_tester.initialize_azure_storage_client(storage_account, 'blob')
          expect(
            client.storage_blob_host
          ).to eq(blob_host_https)
        end
      end

      context "use http" do
        it "should return an azure storage client with setting storage blob host (http)" do
          client = helpers_tester.initialize_azure_storage_client(storage_account, 'blob', true)
          expect(
            client.storage_blob_host
          ).to eq(blob_host_http)
        end
      end
    end

    context "for table" do
      context "when the storage account is standard" do
        context "use https" do
          it "should return an azure storage client with setting table blob host (https)" do
            client = helpers_tester.initialize_azure_storage_client(storage_account, 'table')
            expect(
              client.storage_table_host
            ).to eq(table_host_https)
          end
        end

        context "use http" do
          it "should return an azure storage client with setting table blob host (http)" do
            client = helpers_tester.initialize_azure_storage_client(storage_account, 'table', true)
            expect(
              client.storage_table_host
            ).to eq(table_host_http)
          end
        end
      end

      context "when the storage account is premium" do
        let(:storage_account) {
          {
            :name => storage_account_name,
            :key => storage_access_key,
            :storage_blob_host => 'https://fake-blob-host:443/',
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
        }.to raise_error "The disk size needs to be an integer. The current value is `fake-size'."
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

    context "disk size is larger than 1023 GiB" do
      let(:disk_size) { 1024 * 1024 }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_size(disk_size)
        }.to raise_error "Azure CPI maximum disk size is 1023 GiB"
      end
    end

    context "disk size is a correct value" do
      let(:disk_size) { 30 * 1024 }

      it "should not raise an error" do
        expect {
          helpers_tester.validate_disk_size(disk_size)
        }.not_to raise_error
      end
    end
  end

  describe "#validate_disk_size_type" do
    context "disk size is not an integer" do
      let(:disk_size) { "fake-size" }

      it "should raise an error" do
        expect {
          helpers_tester.validate_disk_size_type(disk_size)
        }.to raise_error "The disk size needs to be an integer. The current value is `fake-size'."
      end
    end

    context "disk size is an integer" do
      let(:disk_size) { 1024 }

      it "should not raise an error" do
        expect {
          helpers_tester.validate_disk_size_type(disk_size)
        }.not_to raise_error
      end
    end
  end

  describe "#is_debug_mode" do
    context "debug_mode is not set" do
      let(:azure_properties) { {} }

      it "should return false" do
        expect(
          helpers_tester.is_debug_mode(azure_properties)
        ).to be false
      end
    end

    context "debug_mode is set to false" do
      let(:azure_properties) { { 'debug_mode' => false } }

      it "should return false" do
        expect(
          helpers_tester.is_debug_mode(azure_properties)
        ).to be false
      end
    end

    context "debug_mode is set to true" do
      let(:azure_properties) { { 'debug_mode' => true } }

      it "should return true" do
        expect(
          helpers_tester.is_debug_mode(azure_properties)
        ).to be true
      end
    end
  end

  describe "#merge_storage_common_options" do
    context "request_id is not set" do
      let(:options) { {} }

      it "should contain request_id" do
        expect(
          helpers_tester.merge_storage_common_options(options)[:request_id]
        ).not_to be_nil
      end
    end

    context "request_id is set" do
      let(:options) { { :request_id => 'fake-request-id' } }

      it "should contain a new request_id" do
        expect(
          helpers_tester.merge_storage_common_options(options)[:request_id]
        ).not_to eq('fake-request-id')
      end
    end
  end

  describe "DiskInfo" do
    context "when instance_type is STANDARD_A0" do
      context "when instance_type is lowercase" do
        it "should return correct values" do
          disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('STANDARD_A0')

          expect(disk_info.size).to eq(30)
          expect(disk_info.count).to eq(1)
        end
      end

      context "when instance_type is uppercase" do
        it "should return correct values" do
          disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('standard_a0')

          expect(disk_info.size).to eq(30)
          expect(disk_info.count).to eq(1)
        end
      end
    end

    context "when instance_type is STANDARD_D15_V2" do
      it "should return correct values" do
        disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('STANDARD_D15_V2')

        expect(disk_info.size).to eq(1023)
        expect(disk_info.count).to eq(40)
      end
    end

    context "when instance_type is unknown" do
      it "should return correct values" do
        disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('unknown')

        expect(disk_info.size).to eq(30)
        expect(disk_info.count).to eq(64)
      end
    end
  end

  describe "StemcellInfo" do
    context "when metadata is not empty" do
      context "but metadata does not contain image" do
        let(:uri) { "fake-uri" }
        let(:metadata) {
          {
            "name" => "fake-name",
            "version" => "fake-version",
            "infrastructure" => "azure",
            "hypervisor" => "hyperv",
            "disk" => "3072",
            "disk_format" => "vhd",
            "container_format" => "bare",
            "os_type" => "linux",
            "os_distro" => "ubuntu",
            "architecture" => "x86_64",
          }
        }

        it "should return correct values" do
          stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
          expect(stemcell_info.uri).to eq("fake-uri")
          expect(stemcell_info.os_type).to eq("linux")
          expect(stemcell_info.name).to eq("fake-name")
          expect(stemcell_info.version).to eq("fake-version")
          expect(stemcell_info.disk_size).to eq(3072)
          expect(stemcell_info.is_light_stemcell?).to be(false)
          expect(stemcell_info.image_reference).to be(nil)
        end
      end

      context "when metadata contains image" do
        let(:uri) { "fake-uri" }
        let(:metadata) {
          {
            "name" => "fake-name",
            "version" => "fake-version",
            "infrastructure" => "azure",
            "hypervisor" => "hyperv",
            "disk" => "3072",
            "disk_format" => "vhd",
            "container_format" => "bare",
            "os_type" => "linux",
            "os_distro" => "ubuntu",
            "architecture" => "x86_64",
            "image" => {"publisher"=>"bosh", "offer"=>"UbuntuServer", "sku"=>"trusty", "version"=>"fake-version"}
          }
        }

        it "should return correct values" do
          stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
          expect(stemcell_info.uri).to eq("fake-uri")
          expect(stemcell_info.os_type).to eq("linux")
          expect(stemcell_info.name).to eq("fake-name")
          expect(stemcell_info.version).to eq("fake-version")
          expect(stemcell_info.disk_size).to eq(3072)
          expect(stemcell_info.is_light_stemcell?).to be(true)
          expect(stemcell_info.image_reference['publisher']).to eq('bosh')
          expect(stemcell_info.image_reference['offer']).to eq('UbuntuServer')
          expect(stemcell_info.image_reference['sku']).to eq('trusty')
          expect(stemcell_info.image_reference['version']).to eq('fake-version')
        end
      end
    end

    context "when metadata is empty" do
      let(:uri) { "fake-uri" }
      let(:metadata) { {} }
      it "should return correct values" do
        stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
        expect(stemcell_info.uri).to eq("fake-uri")
        expect(stemcell_info.os_type).to eq('linux')
        expect(stemcell_info.name).to be(nil)
        expect(stemcell_info.version).to be(nil)
        expect(stemcell_info.disk_size).to eq(3072)
      end
    end
  end

  describe "FileMutex" do
    let(:logger) { Logger.new('/dev/null') }
    let(:file_path) { "/tmp/lock#{SecureRandom.uuid}" }

    context "when the lock does not exist" do
      it "should get the lock" do
        mutex = Bosh::AzureCloud::Helpers::FileMutex.new(file_path, logger, 5)
        expect {
          mutex.synchronize do
            sleep(1)
          end
        }.not_to raise_error
      end
    end
    
    context "when the lock exists and timeouts" do
      before do
        File.open(file_path, "w") {|f| f.write("test") }
      end

      after do
        File.delete(file_path)
      end

      it "should timeout" do
        mutex = Bosh::AzureCloud::Helpers::FileMutex.new(file_path, logger, 5)
        expect {
          mutex.synchronize do
            sleep(1)
          end
        }.to raise_error(/timeout/)
      end
    end
    
    context "when the lock exists initially and is released before timeout" do
      before do
        File.open(file_path, "w") {|f| f.write("test") }
      end

      after do
        File.delete(file_path) if File.exists?(file_path)
      end

      it "should not timeout and continue" do
        mutex = Bosh::AzureCloud::Helpers::FileMutex.new(file_path, logger, 5)
        unlock = Thread.new{
          sleep(2)
          File.delete(file_path)
        }
        expect {
          mutex.synchronize do
            sleep(1)
          end
        }.not_to raise_error
        unlock.join()
      end
    end
  end

  describe "#has_light_stemcell_property?" do
    context "with 'image'" do
      let(:stemcell_properties) {
        {
          'image' => 'fake-image'
        }
      }

      it "should return true" do
        expect(
          helpers_tester.has_light_stemcell_property?(stemcell_properties)
        ).to be(true)
      end
    end

    context "without 'image'" do
      let(:stemcell_properties) {
        {
          'a' => 'b'
        }
      }

      it "should return false" do
        expect(
          helpers_tester.has_light_stemcell_property?(stemcell_properties)
        ).to be(false)
      end
    end
  end

  describe "#is_light_stemcell_id?" do
    context "when stemcell is light" do
      let(:stemcell_id) { 'bosh-light-stemcell-xxx' }

      it "should return true" do
        expect(
          helpers_tester.is_light_stemcell_id?(stemcell_id)
        ).to be(true)
      end
    end

    context "when stemcell is heavy" do
      let(:stemcell_id) { 'bosh-stemcell-xxx' }

      it "should return false" do
        expect(
          helpers_tester.is_light_stemcell_id?(stemcell_id)
        ).to be(false)
       end
     end
   end

   describe "#generate_windows_computer_name" do
    let(:process) { class_double(Process).as_stubbed_const }

    context "when generated raw string is shorter than expect length" do
      before do
        expect_any_instance_of(Time).to receive(:to_f).and_return(1482829740.3734238) #1482829740.3734238 -> 'd5e883lv66u'
        expect(process).to receive(:pid).and_return(6)                                #6 -> '6'
      end

      it "should return string padded with '0' for raw string to make its length eq WINDOWS_VM_NAME_LENGTH" do
        computer_name = helpers_tester.generate_windows_computer_name
        expect(computer_name).to eq('d5e883lv66u0006')
        expect(computer_name.length).to eq(WINDOWS_VM_NAME_LENGTH)
      end
    end

    context "when generated raw string is longer than expect length" do
      before do
        expect_any_instance_of(Time).to receive(:to_f).and_return(1482829740.3734238) #1482829740.3734238 -> 'd5e883lv66u'
        expect(process).to receive(:pid).and_return(6553600)                          #6553600 -> '68000'
      end

      it "should get tail of the string to make its length eq WINDOWS_VM_NAME_LENGTH" do
        computer_name = helpers_tester.generate_windows_computer_name
        expect(computer_name).to eq('5e883lv66u68000')
        expect(computer_name.length).to eq(WINDOWS_VM_NAME_LENGTH)
      end
    end
  end

  describe "#validate_idle_timeout" do
    context "idle_timeout_in_minutes is not an integer" do
      let(:idle_timeout_in_minutes) { "fake-idle-timeout" }

      it "should raise an error" do
        expect {
          helpers_tester.validate_idle_timeout(idle_timeout_in_minutes)
        }.to raise_error "idle_timeout_in_minutes needs to be an integer"
      end
    end

    context "idle_timeout_in_minutes is smaller than 4 minutes" do
      let(:idle_timeout_in_minutes) { 3 }

      it "should raise an error" do
        expect {
          helpers_tester.validate_idle_timeout(idle_timeout_in_minutes)
        }.to raise_error "Minimum idle_timeout_in_minutes is 4 minutes"
      end
    end

    context "idle_timeout_in_minutes is larger than 30 minutes" do
      let(:idle_timeout_in_minutes) { 31 }

      it "should raise an error" do
        expect {
          helpers_tester.validate_idle_timeout(idle_timeout_in_minutes)
        }.to raise_error "Maximum idle_timeout_in_minutes is 30 minutes"
      end
    end

    context "idle_timeout_in_minutes is a correct value" do
      let(:idle_timeout_in_minutes) { 20 }

      it "should not raise an error" do
        expect {
          helpers_tester.validate_idle_timeout(idle_timeout_in_minutes)
        }.not_to raise_error
      end
    end
  end
end
