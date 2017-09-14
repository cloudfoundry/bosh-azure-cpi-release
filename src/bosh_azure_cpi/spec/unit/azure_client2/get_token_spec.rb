require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient2 do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:subscription_id) { mock_azure_properties['subscription_id'] }
  let(:tenant_id) { mock_azure_properties['tenant_id'] }
  let(:client_id) { mock_azure_properties['client_id'] }
  let(:resource_group) { "fake-resource-group-name" }
  let(:authentication_endpoint) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token" }
  let(:api_version) { AZURE_API_VERSION }
  let(:token_uri) { "#{authentication_endpoint}?api-version=#{api_version}" }
  let(:valid_access_token) { "valid-access-token" }
  let(:expires_on) { (Time.now+1800).to_i.to_s }

  describe "#get_token" do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/foo/bar/foo" }
    let(:resource_uri) { "https://management.azure.com/#{url}?api-version=#{api_version}" }
    let(:response_body) {
      {
        "id" => "foo",
        "name" => "name"
      }.to_json
    }

    context "when the client secret is provided" do
      let(:azure_client2) {
        Bosh::AzureCloud::AzureClient2.new(
          mock_azure_properties,
          logger
        )
      }
      let(:token_params) {
        {
          'grant_type'    => 'client_credentials',
          'client_id'     => client_id,
          'resource'      => 'https://management.azure.com/',
          'scope'         => 'user_impersonation',
          'client_secret' => mock_azure_properties['client_secret']
        }
      }

      it "should use the service principal with certificate to get the token" do
        stub_request(:post, token_uri).with(body: URI.encode_www_form(token_params)).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, resource_uri).to_return(
          :status => 200,
          :body => response_body,
          :headers => {})
        expect(
          azure_client2.get_resource_by_id(url, { 'api-version' => api_version })
        ).not_to be_nil
      end
    end

    context "when the client secret is not provided" do
      let(:azure_properties_without_client_secret) {
        properties = mock_azure_properties.clone
        properties.delete('client_secret')
        properties
      }
      let(:azure_client2) {
        Bosh::AzureCloud::AzureClient2.new(
          azure_properties_without_client_secret,
          logger
        )
      }

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
        allow(JWT).to receive(:encode).with(payload, rsa_private, 'RS256', header).and_return(jwt_assertion)
      end

      let(:token_params) {
        {
          'grant_type'            => 'client_credentials',
          'client_id'             => client_id,
          'resource'              => 'https://management.azure.com/',
          'scope'                 => 'user_impersonation',
          'client_assertion_type' => 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
          'client_assertion'      => jwt_assertion
        }
      }

      it "should use the service principal with certificate to get the token" do
        stub_request(:post, token_uri).with(body: URI.encode_www_form(token_params)).to_return(
          :status => 200,
          :body => {
            "access_token" => valid_access_token,
            "expires_on" => expires_on
          }.to_json,
          :headers => {})
        stub_request(:get, resource_uri).to_return(
          :status => 200,
          :body => response_body,
          :headers => {})
        expect(
          azure_client2.get_resource_by_id(url, { 'api-version' => api_version })
        ).not_to be_nil
      end
    end
  end
end
