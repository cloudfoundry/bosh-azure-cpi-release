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

  describe "#ignore_exception" do
    context "when no exception type is specified" do
      it "should ignore any exception" do
        expect{
          helpers_tester.ignore_exception do
            raise Exception
          end
        }.not_to raise_error
      end
    end

    context "when the exception type is specified" do
      it "should ignore the specified exception and raise other exception" do
        expect{
          helpers_tester.ignore_exception(Errno::EEXIST) do
            raise Errno::EEXIST
          end
        }.not_to raise_error
        expect{
          helpers_tester.ignore_exception(Errno::EEXIST) do
            raise Errno::ENOENT
          end
        }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "#bosh_jobs_dir" do
    context "when the environment variable BOSH_JOBS_DIR exists" do
      let(:bosh_jobs_dir) { ".bosh_init/installations/a3ee66ec-6f00-4aab-632d-f6d4c5dc5f5b/jobs" }
      before do
        allow(ENV).to receive(:[]).with("BOSH_JOBS_DIR").and_return(bosh_jobs_dir)
      end

      it "should return the environment variable BOSH_JOBS_DIR" do
        expect(helpers_tester.bosh_jobs_dir).to eq(bosh_jobs_dir)
      end
    end

    context "when the environment variable BOSH_JOBS_DIR doesn't exist" do
      it "should return /var/vcap/jobs" do
        expect(helpers_tester.bosh_jobs_dir).to eq("/var/vcap/jobs")
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

      context "when azure_stack.authentication is AzureChinaClouadAD" do
        before do
          azure_properties['azure_stack']['authentication'] = 'AzureChinaCloudAD'
        end

        it "should return Azure China Cloud authentication endpoint and api version" do
          expect(
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          ).to eq(["https://login.chinacloudapi.cn/fake-tenant-id/oauth2/token", api_version])
        end
      end

      context "when azure_stack.authentication is ADFS" do
        before do
          azure_properties['azure_stack']['authentication'] = 'ADFS'
        end

        it "should return ADFS authentication endpoint and api version" do
          expect(
            helpers_tester.get_azure_authentication_endpoint_and_api_version(azure_properties)
          ).to eq(["https://adfs.fake-domain/adfs/oauth2/token", azure_stack_api_version])
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

  describe "#get_service_principal_certificate_path" do
    context "when the environment variable BOSH_JOBS_DIR exists" do
      let(:bosh_jobs_dir) { ".bosh_init/installations/a3ee66ec-6f00-4aab-632d-f6d4c5dc5f5b/jobs" }
      before do
        allow(ENV).to receive(:[]).with("BOSH_JOBS_DIR").and_return(bosh_jobs_dir)
      end

      it "should return a path under BOSH_JOBS_DIR" do
        expect(helpers_tester.get_service_principal_certificate_path).to eq("#{bosh_jobs_dir}/azure_cpi/config/service_principal_certificate.pem")
      end
    end

    context "when the environment variable BOSH_JOBS_DIR doesn't exist" do
      it "should return a path under /var/vcap/jobs" do
        expect(helpers_tester.get_service_principal_certificate_path).to eq("/var/vcap/jobs/azure_cpi/config/service_principal_certificate.pem")
      end
    end
  end

  describe "#get_jwt_assertion" do
    let(:authentication_endpoint) { "fake-endpoint" }
    let(:client_id) { "3d343186-e27c-4db1-b59e-50bf7b366f61" }
    let(:certificate_data) { "fake-cert-data" }
    let(:cert) { instance_double(OpenSSL::X509::Certificate) }
    let(:thumbprint) { "12f0d2b95eb4d0ad81892c9d9fcc45a89c324cbd" }
    let(:x5t) { "EvDSuV600K2BiSydn8xFqJwyTL0=" } # x5t is the Base64 UrlEncoding of thumbprint
    let(:now) { Time.now }
    let(:jti) { "b55b54ac-7494-449b-94b2-d7bff0285837" }
    let(:header) {
      {
        "alg": "RS256",
        "typ": "JWT",
        "x5t": x5t
      }
    }
    let(:payload) {
      {
        "aud": authentication_endpoint,
        "exp": (now + 3600).strftime("%s"),
        "iss": client_id,
        "jti": jti,
        "nbf": (now - 90).strftime("%s"),
        "sub": client_id
      }
    }
    let(:rsa_private) { "fake-rsa-private" }
    let(:jwt_assertion) { "fake-jwt-assertion" }

    before do
      allow(File).to receive(:read).and_return(certificate_data)
      allow(OpenSSL::X509::Certificate).to receive(:new).with(certificate_data).and_return(cert)
      allow(cert).to receive(:to_der)
      allow(OpenSSL::Digest::SHA1).to receive(:new).and_return(thumbprint)
      allow(SecureRandom).to receive(:uuid).and_return(jti)
      allow(Time).to receive(:now).and_return(now)
      allow(OpenSSL::PKey::RSA).to receive(:new).with(certificate_data).and_return(rsa_private)
    end

    it "should encode the payload with the private key" do
      expect(JWT).to receive(:encode).with(payload, rsa_private, 'RS256', header).and_return(jwt_assertion)
      expect(helpers_tester.get_jwt_assertion(authentication_endpoint, client_id)).to eq(jwt_assertion)
    end

    context "when JWT throws an error when encoding" do
      it "should raise an error" do
        expect(JWT).to receive(:encode).with(payload, rsa_private, 'RS256', header).and_raise("JWT-ENCODING-ERROR")
        expect {
          helpers_tester.get_jwt_assertion(authentication_endpoint, client_id)
        }.to raise_error /Failed to get the jwt assertion: .*JWT-ENCODING-ERROR/
      end
    end
  end

  describe "#initialize_azure_storage_client" do
    let(:azure_client) { instance_double(Azure::Storage::Client) }
    let(:storage_account_name) { "fake-storage-account-name" }
    let(:storage_account_key) { "fake-storage-account-key" }
    let(:storage_dns_suffix) { "fake-storage-dns-suffix" }
    let(:storage_account) {
      {
        :name => storage_account_name,
        :key  => storage_account_key,
        :storage_blob_host => "https://#{storage_account_name}.blob.#{storage_dns_suffix}"
      }
    }

    context "when the environment is not AzureStack" do
      let(:azure_properties) {
        {
          "environment" => "AzureCloud"
        }
      }
      let(:options) {
        {
          :storage_account_name => storage_account_name,
          :storage_access_key   => storage_account_key,
          :storage_dns_suffix   => storage_dns_suffix,
          :user_agent_prefix    => "BOSH-AZURE-CPI"
        }
      }

      it "should create the storage client with the correct options" do
        expect(Azure::Storage::Client).to receive(:create).with(options).
          and_return(azure_client)
        expect(
          helpers_tester.initialize_azure_storage_client(storage_account, azure_properties)
        ).to eq(azure_client)
      end
    end

    context "when the environment is AzureStack" do
      let(:azure_stack_domain) { "fake-azure-stack-domain" }
      let(:azure_properties) {
        {
          "environment" => "AzureStack",
          "azure_stack" => {
            "domain" => azure_stack_domain
          }
        }
      }
      let(:options) {
        {
          :storage_account_name       => storage_account_name,
          :storage_access_key         => storage_account_key,
          :storage_dns_suffix         => storage_dns_suffix,
          :ca_file                    => "/var/vcap/jobs/azure_cpi/config/azure_stack_ca_cert.pem",
          :user_agent_prefix          => "BOSH-AZURE-CPI"
        }
      }

      it "should create the storage client with the correct options" do
        expect(Azure::Storage::Client).to receive(:create).with(options).
          and_return(azure_client)
        expect(
          helpers_tester.initialize_azure_storage_client(storage_account, azure_properties)
        ).to eq(azure_client)
      end
    end
  end

  describe "#get_ca_cert_path" do
    context "when the environment variable BOSH_JOBS_DIR exists" do
      let(:bosh_jobs_dir) { ".bosh_init/installations/a3ee66ec-6f00-4aab-632d-f6d4c5dc5f5b/jobs" }
      before do
        allow(ENV).to receive(:[]).with("BOSH_JOBS_DIR").and_return(bosh_jobs_dir)
      end

      it "should return a path under BOSH_JOBS_DIR" do
        expect(helpers_tester.get_ca_cert_path).to eq("#{bosh_jobs_dir}/azure_cpi/config/azure_stack_ca_cert.pem")
      end
    end

    context "when the environment variable BOSH_JOBS_DIR doesn't exist" do
      it "should return a path under /var/vcap/jobs" do
        expect(helpers_tester.get_ca_cert_path).to eq("/var/vcap/jobs/azure_cpi/config/azure_stack_ca_cert.pem")
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
      context "when instance_type is uppercase" do
        it "should return correct values" do
          disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('STANDARD_A0')

          expect(disk_info.size).to eq(30)
          expect(disk_info.count).to eq(1)
        end
      end

      context "when instance_type is lowercase" do
        it "should return correct values" do
          disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('standard_a0')

          expect(disk_info.size).to eq(30)
          expect(disk_info.count).to eq(1)
        end
      end
    end

    context "when instance_type is a known VM size" do
      it "should return correct values" do
        # No matter which VM size is used
        disk_info = Bosh::AzureCloud::Helpers::DiskInfo.for('STANDARD_D15_V2')

        expect(disk_info.size).to eq(1000)
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
            "disk" => "3072",
            "os_type" => "linux",
          }
        }

        it "should return correct values" do
          stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
          expect(stemcell_info.uri).to eq("fake-uri")
          expect(stemcell_info.os_type).to eq("linux")
          expect(stemcell_info.name).to eq("fake-name")
          expect(stemcell_info.version).to eq("fake-version")
          expect(stemcell_info.image_size).to eq(3072)
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
            "disk" => "3072",
            "os_type" => "linux",
            "image" => {"publisher"=>"bosh", "offer"=>"UbuntuServer", "sku"=>"trusty", "version"=>"fake-version"}
          }
        }

        it "should return correct values" do
          stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
          expect(stemcell_info.uri).to eq("fake-uri")
          expect(stemcell_info.os_type).to eq("linux")
          expect(stemcell_info.name).to eq("fake-name")
          expect(stemcell_info.version).to eq("fake-version")
          expect(stemcell_info.image_size).to eq(3072)
          expect(stemcell_info.is_light_stemcell?).to be(true)
          expect(stemcell_info.image_reference['publisher']).to eq('bosh')
          expect(stemcell_info.image_reference['offer']).to eq('UbuntuServer')
          expect(stemcell_info.image_reference['sku']).to eq('trusty')
          expect(stemcell_info.image_reference['version']).to eq('fake-version')
        end
      end

      context "when os_type is linux" do
        context "when disk is not specified" do
          let(:uri) { "fake-uri" }
          let(:metadata) {
            {
              "name" => "fake-name",
              "version" => "fake-version",
              "os_type" => "linux",
            }
          }

          it "should return the default image size" do
            stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
            expect(stemcell_info.os_type).to eq("linux")
            expect(stemcell_info.image_size).to eq(3 * 1024)
          end
        end

        context "when disk is specified" do
          let(:uri) { "fake-uri" }
          let(:metadata) {
            {
              "name" => "fake-name",
              "version" => "fake-version",
              "disk" => "12345",
              "os_type" => "linux",
            }
          }

          it "should return the image size specified in the stemcell properties" do
            stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
            expect(stemcell_info.os_type).to eq("linux")
            expect(stemcell_info.image_size).to eq(12345)
          end
        end
      end

      context "when os_type is windows" do
        context "when disk is not specified" do
          let(:uri) { "fake-uri" }
          let(:metadata) {
            {
              "name" => "fake-name",
              "version" => "fake-version",
              "os_type" => "windows",
            }
          }

          it "should return the default image size" do
            stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
            expect(stemcell_info.os_type).to eq("windows")
            expect(stemcell_info.image_size).to eq(128 * 1024)
          end
        end

        context "when disk is specified" do
          let(:uri) { "fake-uri" }
          let(:metadata) {
            {
              "name" => "fake-name",
              "version" => "fake-version",
              "disk" => "12345",
              "os_type" => "windows",
            }
          }

          it "should return the image size specified in the stemcell properties" do
            stemcell_info = Bosh::AzureCloud::Helpers::StemcellInfo.new(uri, metadata)
            expect(stemcell_info.os_type).to eq("windows")
            expect(stemcell_info.image_size).to eq(12345)
          end
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
        expect(stemcell_info.image_size).to eq(3072)
      end
    end
  end

  describe "#FileMutex" do
    let(:logger) { Logger.new('/dev/null') }
    let(:lock_dir) { '/tmp/azure_cpi' }
    let(:lock_name) { "fake-lock-name" }
    let(:file_path) { "#{lock_dir}/#{lock_name}" }
    let(:expired) { 5 }
    let(:mtime) { 100 } # The value doesn't matter
    let(:mutex) { Bosh::AzureCloud::Helpers::FileMutex.new(lock_name, logger, expired) }

    context "#lock" do
      context "when the lock file does not exist" do
        before do
          allow(File).to receive(:mtime).with(file_path).and_raise(Errno::ENOENT)
        end

        context "when it creates the lock file successfully" do
          let(:file_handler) { double("file_handler") }
          before do
            allow(IO).to receive(:sysopen)
            allow(IO).to receive(:open).and_return(file_handler)
            allow(file_handler).to receive(:syswrite)
            allow(file_handler).to receive(:close)
          end

          it "should get the lock" do
            expect(mutex.lock).to eq(true)
            expect(mutex.instance_variable_get(:@is_locked)).to be(true)
          end
        end

        context "when it fails to create the lock file" do
          before do
            allow(IO).to receive(:sysopen).and_raise(Errno::EEXIST)
          end

          it "should not get the lock" do
            expect(mutex.lock).to eq(false)
            expect(mutex.instance_variable_get(:@is_locked)).to be(false)
          end
        end
      end

      context "when the lock file exists" do
        before do
          allow(File).to receive(:mtime).with(file_path).and_return(mtime)
        end

        context "when the lock doesn't timeout" do
          before do
            allow(File).to receive(:mtime).with(file_path).and_return(mtime)
            allow(Time).to receive(:new).and_return(mtime + expired - 1)
          end

          it "should not get the lock" do
            expect(IO).not_to receive(:sysopen)
            expect(mutex.lock).to eq(false)
            expect(mutex.instance_variable_get(:@is_locked)).to be(false)
          end
        end

        context "when the lock timeouts" do
          before do
            allow(File).to receive(:mtime).with(file_path).and_return(mtime)
            allow(Time).to receive(:new).and_return(mtime + expired + 1)
          end

          it "should raise a timeout exception" do
            expect(IO).not_to receive(:sysopen)
            expect {
              mutex.lock
            }.to raise_error(Bosh::AzureCloud::Helpers::LockTimeoutError)
            expect(mutex.instance_variable_get(:@is_locked)).to be(false)
          end
        end
      end
    end

    context "#wait" do
      context "when the lock has been acquired" do
        before do
          allow(File).to receive(:mtime).with(file_path).and_raise(Errno::ENOENT)
        end

        it "should return true" do
          expect(mutex.wait).to eq(true)
        end
      end

      context "when the lock has been acquired by other process initially, and released later" do
        before do
          allow(Time).to receive(:new).and_return(mtime + expired - 1)
          count = 0
          allow(File).to receive(:mtime) do
            count += 1
            count == 1 ? mtime : raise(Errno::ENOENT)
          end
        end

        it "should return true" do
          expect(File).to receive(:mtime).with(file_path).twice
          expect(mutex.wait).to eq(true)
        end
      end

      context "when the lock has been acquired initially, and it timeouts" do
        before do
          allow(File).to receive(:mtime).with(file_path).and_return(mtime)
          allow(Time).to receive(:new).and_return(mtime + expired + 1)
        end

        it "should return true" do
          expect {
            mutex.wait
          }.to raise_error(Bosh::AzureCloud::Helpers::LockTimeoutError)
        end
      end
    end

    context "#unlock" do
      context "when it deletes the lock file successfully" do
        it "should release the lock" do
          expect(File).to receive(:delete).with(file_path)
          expect {
            mutex.unlock
          }.not_to raise_error
          expect(mutex.instance_variable_get(:@is_locked)).to be(false)
        end
      end

      context "when the lock file is not found" do
        before do
          allow(File).to receive(:delete).and_raise(Errno::ENOENT)
        end

        it "should raise an error" do
          expect {
            mutex.unlock
          }.to raise_error(Bosh::AzureCloud::Helpers::LockNotFoundError)
        end
      end

      context "when it fails to delete the lock file due to other errors" do
        before do
          allow(File).to receive(:delete).and_raise(StandardError)
        end

        it "should raise an error" do
          expect {
            mutex.unlock
          }.to raise_error(StandardError)
        end
      end
    end

    context "#update" do
      context "when the lock file is not owned by the process" do
        before do
          mutex.instance_variable_set(:@is_locked, false)
        end

        it "should raise an error" do
          expect {
            mutex.update
          }.to raise_error(Bosh::AzureCloud::Helpers::LockNotOwnedError)
        end
      end

      context "when the lock file is owned by the process" do
        before do
          mutex.instance_variable_set(:@is_locked, true)
        end

        context "when the lock file is updated successfully" do
          it "should not raise an error" do
            expect(File).to receive(:open).with(file_path, 'wb')
            expect {
              mutex.update
            }.not_to raise_error
          end
        end

        context "when the lock file is not found" do
          before do
            allow(File).to receive(:open).and_raise(Errno::ENOENT)
          end

          it "should raise an error" do
            expect {
              mutex.update
            }.to raise_error(Bosh::AzureCloud::Helpers::LockNotFoundError)
          end
        end

        context "when it fails to update the lock file due to other errors" do
          before do
            allow(File).to receive(:open).and_raise(StandardError)
          end

          it "should raise an error" do
            expect {
              mutex.update
            }.to raise_error(StandardError)
          end
        end
      end
    end
  end

  describe "#ReadersWriterLock" do
    let(:lock_name)            { "fake-readers-writer-lock-name" }
    let(:logger)               { Logger.new('/dev/null') }
    let(:expired)              { 5 }
    let(:rwlock)               { Bosh::AzureCloud::Helpers::ReadersWriterLock.new(lock_name, logger, expired) }
    let(:readers_lock_name)    { "#{lock_name}-readers" }
    let(:writer_lock_name)     { "#{lock_name}-writer" }
    let(:readers_mutex)        { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
    let(:writer_mutex)         { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
    let(:counter_file)         { "/tmp/azure_cpi/#{lock_name}-counter" }
    let(:counter_file_handler) { instance_double(File) }

    before do
      allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).
        with(readers_lock_name, logger, expired).and_return(readers_mutex)
      allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).
        with(writer_lock_name, logger, expired).and_return(writer_mutex)
      allow(File).to receive(:open).and_yield(counter_file_handler)
    end

    context "#acquire_read_lock" do
      context "when the readers mutex is locked at the first time" do
        before do
          allow(readers_mutex).to receive(:lock).and_return(true)
        end

        context "when the counter file doesn't exist" do
          before do
            allow(File).to receive(:exists?).with(counter_file).and_return(false)
          end

          it "should update the counter to 1, and lock the writer mutex" do
            expect(readers_mutex).not_to receive(:wait)
            expect(counter_file_handler).to receive(:write).with("1")
            expect(writer_mutex).to receive(:lock).and_return(true)
            expect(readers_mutex).to receive(:unlock)

            expect {
              rwlock.acquire_read_lock
            }.not_to raise_error
          end
        end

        context "when the counter file exists" do
          let(:counter) { 1 }
          before do
            allow(File).to receive(:exists?).with(counter_file).and_return(true)
            allow(counter_file_handler).to receive(:read).and_return("#{counter}")
          end

          it "should increase the counter, and should not lock the writer mutex" do
            expect(readers_mutex).not_to receive(:wait)
            expect(counter_file_handler).to receive(:write).with("#{counter+1}")
            expect(writer_mutex).not_to receive(:lock)
            expect(readers_mutex).to receive(:unlock)

            expect {
              rwlock.acquire_read_lock
            }.not_to raise_error
          end
        end
      end

      context "when the readers mutex is locked at the second time" do
        before do
          allow(readers_mutex).to receive(:lock).and_return(false, true)
          allow(File).to receive(:exists?).with(counter_file).and_return(false)
        end

        it "should update the counter to 1, and lock the writer mutex" do
          expect(readers_mutex).to receive(:wait).and_return(true)
          expect(counter_file_handler).to receive(:write).with("1")
          expect(writer_mutex).to receive(:lock).and_return(true)
          expect(readers_mutex).to receive(:unlock)

          expect {
            rwlock.acquire_read_lock
          }.not_to raise_error
        end
      end

      context "when the readers mutex can't be locked" do
        before do
          allow(readers_mutex).to receive(:lock).and_return(false)
          allow(readers_mutex).to receive(:wait).and_raise(Bosh::AzureCloud::Helpers::LockTimeoutError)
        end

        it "should raise a timeout" do
          expect {
            rwlock.acquire_read_lock
          }.to raise_error(Bosh::AzureCloud::Helpers::LockTimeoutError)
        end
      end
    end

    context "#release_read_lock" do
      context "when the readers mutex is locked at the first time" do
        before do
          allow(readers_mutex).to receive(:lock).and_return(true)
          allow(File).to receive(:exists?).with(counter_file).and_return(true)
        end

        context "when the counter is greater than 1" do
          let(:counter) { 3 }
          before do
            allow(counter_file_handler).to receive(:read).and_return("#{counter}")
          end

          it "should decrease the counter, and should not unlock the writer mutex" do
            expect(readers_mutex).not_to receive(:wait)
            expect(counter_file_handler).to receive(:write).with("#{counter-1}")
            expect(File).not_to receive(:delete)
            expect(writer_mutex).not_to receive(:unlock)
            expect(readers_mutex).to receive(:unlock)

            expect {
              rwlock.release_read_lock
            }.not_to raise_error
          end
        end

        context "when the counter is 1" do
          before do
            allow(counter_file_handler).to receive(:read).and_return("1")
          end

          it "should decrease the counter to 0, and should unlock the writer mutex" do
            expect(readers_mutex).not_to receive(:wait)
            expect(counter_file_handler).to receive(:write).with("0")
            expect(File).to receive(:delete)
            expect(writer_mutex).to receive(:unlock)
            expect(readers_mutex).to receive(:unlock)

            expect {
              rwlock.release_read_lock
            }.not_to raise_error
          end
        end
      end

      context "when the readers mutex is locked at the second time" do
        let(:counter) { 3 }
        before do
          allow(readers_mutex).to receive(:lock).and_return(false, true)
          allow(File).to receive(:exists?).with(counter_file).and_return(true)
          allow(counter_file_handler).to receive(:read).and_return("#{counter}")
        end

        it "should decrease the counter, and should not unlock the writer mutex" do
          expect(readers_mutex).to receive(:wait).and_return(true)
          expect(counter_file_handler).to receive(:write).with("#{counter-1}")
          expect(File).not_to receive(:delete)
          expect(writer_mutex).not_to receive(:unlock)
          expect(readers_mutex).to receive(:unlock)

          expect {
            rwlock.release_read_lock
          }.not_to raise_error
        end
      end

      context "when the readers mutex can't be locked" do
        before do
          allow(readers_mutex).to receive(:lock).and_return(false)
          allow(readers_mutex).to receive(:wait).and_raise(Bosh::AzureCloud::Helpers::LockTimeoutError)
        end

        it "should raise a timeout" do
          expect {
            rwlock.release_read_lock
          }.to raise_error(Bosh::AzureCloud::Helpers::LockTimeoutError)
        end
      end
    end

    context "#acquire_write_lock" do
      before do
        allow(writer_mutex).to receive(:lock).and_return(true)
      end

      it "should acquire the writer lock" do
        expect(rwlock.acquire_write_lock).to be(true)
      end
    end

    context "#release_write_lock" do
      before do
        allow(writer_mutex).to receive(:unlock)
      end

      it "should release the writer lock" do
        expect {
          rwlock.release_write_lock
        }.not_to raise_error
      end
    end
  end

  describe "#get_storage_account_type_by_instance_type" do
    context "when the instance type is UPCASE" do
      let(:instance_type) { "STANDARD_DS1" }

      it "should return Premium_LRS" do
        expect(
          helpers_tester.get_storage_account_type_by_instance_type(instance_type)
        ).to be(Bosh::AzureCloud::Helpers::STORAGE_ACCOUNT_TYPE_PREMIUM_LRS)
      end
    end

    context "when the instance type is DOWNCASE" do
      let(:instance_type) { "standard_ds1" }

      it "should return Premium_LRS" do
        expect(
          helpers_tester.get_storage_account_type_by_instance_type(instance_type)
        ).to be(Bosh::AzureCloud::Helpers::STORAGE_ACCOUNT_TYPE_PREMIUM_LRS)
      end
    end

    context "when the instance type doesn't support SSD disk" do
      let(:instance_type) { "Standard_D1" }

      it "should return Standard_LRS" do
        expect(
          helpers_tester.get_storage_account_type_by_instance_type(instance_type)
        ).to be(Bosh::AzureCloud::Helpers::STORAGE_ACCOUNT_TYPE_STANDARD_LRS)
      end
    end

    context "when the instance type supports SSD disk" do
      let(:instance_types) {
        [
          "Standard_DS1", "Standard_DS2", "Standard_DS3", "Standard_DS4",
          "Standard_DS1_v2", "Standard_DS2_v2", "Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2",
          "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3", "Standard_D32s_v3", "Standard_D64s_v3",
          "Standard_GS1", "Standard_GS2", "Standard_GS3", "Standard_GS4", "Standard_GS5",
          "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms", "Standard_B4ms", "Standard_B8ms",
          "Standard_F1s", "Standard_F2s", "Standard_F4s", "Standard_F8s", "Standard_F16s",
          "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3", "Standard_E32s_v3", "Standard_E64s_v3", "Standard_E64is_v3",
          "Standard_L4s", "Standard_L8s", "Standard_L16s", "Standard_L32s",
        ]
      }

      it "should return Premium_LRS" do
        instance_types.each do |instance_type|
          expect(
            helpers_tester.get_storage_account_type_by_instance_type(instance_type)
          ).to be(Bosh::AzureCloud::Helpers::STORAGE_ACCOUNT_TYPE_PREMIUM_LRS)
        end
      end
    end
  end

  describe "#is_stemcell_storage_account?" do
    context "when the tags are exactly same with the stemcell storage account tags" do
      let(:tags) { Bosh::AzureCloud::Helpers::STEMCELL_STORAGE_ACCOUNT_TAGS }

      it "should return true" do
        expect(
          helpers_tester.is_stemcell_storage_account?(tags)
        ).to be(true)
      end
    end

    context "when the tags are a superset of the stemcell storage account tags" do
      let(:tags) { Bosh::AzureCloud::Helpers::STEMCELL_STORAGE_ACCOUNT_TAGS.clone.merge({'foo'=>'bar'}) }

      it "should return true" do
        expect(
          helpers_tester.is_stemcell_storage_account?(tags)
        ).to be(true)
      end
    end

    context "when the tags don't include the stemcell storage account tags" do
      let(:tags) { {'foo'=>'bar'} }

      it "should return false" do
        expect(
          helpers_tester.is_stemcell_storage_account?(tags)
        ).to be(false)
      end
    end
  end

  describe "#is_ephemeral_disk?" do
    context "when the disk name ends with the ephemeral disk postfix" do
      let(:disk_name) { "fake-#{Bosh::AzureCloud::Helpers::EPHEMERAL_DISK_POSTFIX}" }

      it "should return true" do
        expect(
          helpers_tester.is_ephemeral_disk?(disk_name)
        ).to be(true)
      end
    end

    context "when the disk name doesn't end with the ephemeral disk postfix" do
      let(:disk_name) { "fake-disk-name" }

      it "should return false" do
        expect(
          helpers_tester.is_ephemeral_disk?(disk_name)
        ).to be(false)
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
