# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      logger
    )
  end
  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:default_resource_group) { mock_azure_config.resource_group_name }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { 'fake-vm-name' }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  describe '#rest_api_url' do
    it 'returns the right url if all parameters are given' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      others = 'd'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               name: name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/c/d")
    end

    it 'returns the right url if resource group name is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      others = 'd'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               name: name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group}/providers/a/b/c/d")
    end

    it 'returns the right url if name is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      others = 'd'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/d")
    end

    it 'returns the right url if others is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               name: name
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/c")
    end

    it 'returns the right url if resource_group_name, name and others are all not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group}/providers/a/b")
    end
  end

  describe '#update_tags_of_virtual_machine' do
    let(:resource_name) { 'some-resource-name' }
    let(:resource_group_name) { 'some-resource-group-name' }
    let(:resource_url) { 'some-resource-url' }

    before do
      # it's pretty gross to do so much stubbing of the unit under test, but ...
      # no-one has bothered to set up a harness for this and the behavior of the stubbed functions does not affect the
      # functionality we are interested in here (it could be changed in the future so it does, but ... please don't :) )
      allow(azure_client).to receive(:rest_api_url)
        .with(Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_COMPUTE,
              Bosh::AzureCloud::AzureClient::REST_API_VIRTUAL_MACHINES,
              { resource_group_name: 'some-resource-group-name', name: resource_name }).and_return(resource_url)
      allow(azure_client).to receive(:get_resource_by_id).with(resource_url).and_return(vm_properties)
    end

    context 'when identity is UserAssigned and there are values in userAssignedIdentities' do
      let(:vm_properties) do
        {
          'identity' => {
            'type' => Bosh::AzureCloud::AzureClient::MANAGED_IDENTITY_TYPE_USER_ASSIGNED,
            'userAssignedIdentities' => {
              '/some/user-assigned/identity/url' => { 'principalId' => 'some-guid', 'clientId' => 'some-guid' }
            }
          },
          'tags' => {}
        }
      end

      it 'should correctly remove invalid userAssignedIdentities values if they exist' do
        expected_properties = {
          'identity' => {
            'type' => Bosh::AzureCloud::AzureClient::MANAGED_IDENTITY_TYPE_USER_ASSIGNED,
            'userAssignedIdentities' => {
              '/some/user-assigned/identity/url' => {}
            }
          },
          'tags' => { 'added' => 'tags' }
        }
        expect(azure_client).to receive(:http_put).with('some-resource-url', expected_properties)
        azure_client.update_tags_of_virtual_machine(resource_group_name, resource_name, { 'added' => 'tags' })
      end
    end

    context 'with SystemAssigned identities' do
      let(:vm_properties) do
        {
          'identity' => {
            'type' => Bosh::AzureCloud::AzureClient::MANAGED_IDENTITY_TYPE_SYSTEM_ASSIGNED
          },
          'tags' => {}
        }
      end

      it 'should not fail' do
        expected_properties = {
          'identity' => {
            'type' => Bosh::AzureCloud::AzureClient::MANAGED_IDENTITY_TYPE_SYSTEM_ASSIGNED
          },
          'tags' => { 'added' => 'tags' }
        }
        expect(azure_client).to receive(:http_put).with('some-resource-url', expected_properties)
        azure_client.update_tags_of_virtual_machine(resource_group_name, resource_name, { 'added' => 'tags' })
      end
    end

    context 'with no Identity hash' do
      let(:vm_properties) do
        {
          'tags' => {}
        }
      end

      it 'should not fail' do
        expected_properties = {
          'tags' => { 'added' => 'tags' }
        }
        expect(azure_client).to receive(:http_put).with('some-resource-url', expected_properties)
        azure_client.update_tags_of_virtual_machine(resource_group_name, resource_name, { 'added' => 'tags' })
      end
    end
  end

  describe '#update_managed_disk' do
    let(:resource_name) { 'xtreme-disk' }
    let(:resource_group_name) { 'xtreme-resource-group-name' }
    let(:resource_url) { 'some-resource-url' }

    before do
      allow(azure_client).to receive(:rest_api_url)
        .with(Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_COMPUTE,
              Bosh::AzureCloud::AzureClient::REST_API_DISKS,
              { resource_group_name: resource_group_name, name: resource_name }).and_return(resource_url)
      allow(azure_client).to receive(:http_patch).with(resource_url, anything)
    end

    it 'should update the disk tags' do
      tags = { 'foo' => 'bar' }
      expect(azure_client).to receive(:http_patch).with(resource_url, { 'tags' => tags })

      azure_client.update_managed_disk(resource_group_name, resource_name, { tags: tags })
    end

    it 'should update the location' do
      location = 'eastus'
      expect(azure_client).to receive(:http_patch).with(resource_url, { 'location' => location })

      azure_client.update_managed_disk(resource_group_name, resource_name, { location: location })
    end

    it 'should update the account type' do
      account_type = 'Standard_LRS'
      expect(azure_client).to receive(:http_patch).with(resource_url, { 'sku' => { 'name' => account_type } })

      azure_client.update_managed_disk(resource_group_name, resource_name, { account_type: account_type })
    end

    it 'should update the disks size iops and mbps' do
      size = 4
      iops = 3100
      mbps = 150
      expected_properties = {
        'properties' => {
          'diskSizeGB' => size,
          'diskIOPSReadWrite' => iops,
          'diskMBpsReadWrite' => mbps
        }
      }
      expect(azure_client).to receive(:http_patch).with(resource_url, expected_properties)

      azure_client.update_managed_disk(resource_group_name, resource_name, { disk_size: size, iops: iops, mbps: mbps })
    end

    it 'should not send a request if no params to update' do
      expect(azure_client).not_to receive(:http_patch)

      azure_client.update_managed_disk(resource_group_name, resource_name, {})
    end

    it 'should fail if no disk name is passed' do
      expect do
        azure_client.update_managed_disk(resource_group_name, '', { 'anything' => 'anything' })
      end.to raise_error(/Disk parameter 'name' must not be empty/)
    end
  end

  describe '#_parse_name_from_id' do
    context 'when id is empty' do
      it 'should raise an error' do
        id = ''
        expect do
          azure_client.send(:_parse_name_from_id, id)
        end.to raise_error(/"#{id}" is not a valid URL./)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d'
      it 'should raise an error' do
        expect do
          azure_client.send(:_parse_name_from_id, id)
        end.to raise_error(/"#{id}" is not a valid URL./)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d/e' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d/e'
      it 'should return the name' do
        result = {}
        result[:subscription_id] = 'a'
        result[:resource_group_name] = 'b'
        result[:provider_name] = 'c'
        result[:resource_type] = 'd'
        result[:resource_name] = 'e'
        expect(azure_client.send(:_parse_name_from_id, id)).to eq(result)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d/e/f' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d/e/f'
      it 'should return the name' do
        result = {}
        result[:subscription_id] = 'a'
        result[:resource_group_name] = 'b'
        result[:provider_name] = 'c'
        result[:resource_type] = 'd'
        result[:resource_name] = 'e'
        expect(azure_client.send(:_parse_name_from_id, id)).to eq(result)
      end
    end
  end

  describe '#get_resource_by_id' do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/foo/bar/foo" }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{api_version}" }
    let(:response_body) do
      {
        'id' => 'foo',
        'name' => 'name'
      }.to_json
    end

    context 'when token is valid, getting response succeeds' do
      context 'when no error happens' do
        it 'should return null if response body is null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).to be_nil
        end

        it 'should return the resource if response body is not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: response_body,
            headers: {}
          )
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).not_to be_nil
        end
      end
    end

    context 'when token is invalid' do
      it 'should raise an error if token is not gotten' do
        stub_request(:post, token_uri).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/get_token - http code: 404/)
      end

      it 'should raise an error if tenant_id, client_id or client_secret/certificate is invalid' do
        stub_request(:post, token_uri).to_return(
          status: 401,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error %r{get_token - http code: 401. Azure authentication failed: Invalid tenant_id, client_id or client_secret/certificate.}
      end

      it 'should raise an error if the request is invalid' do
        stub_request(:post, token_uri).to_return(
          status: 400,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error %r{get_token - http code: 400. Azure authentication failed: Bad request. Please assure no typo in values of tenant_id, client_id or client_secret/certificate.}
      end

      it 'should raise an error if authentication retry fails' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 401,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/Azure authentication failed: Token is invalid./)
      end
    end

    context 'when token expired' do
      context 'when authentication retry succeeds' do
        before do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return({
                                                       status: 401,
                                                       body: 'The token expired'
                                                     },
                                                     status: 200,
                                                     body: response_body,
                                                     headers: {})
        end

        it 'should return the resource' do
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).not_to be_nil
        end
      end

      context 'when authentication retry fails' do
        before do
          stub_request(:post, token_uri).to_return({
                                                     status: 200,
                                                     body: {
                                                       'access_token' => valid_access_token,
                                                       'expires_on' => expires_on
                                                     }.to_json,
                                                     headers: {}
                                                   },
                                                   status: 401,
                                                   body: '',
                                                   headers: {})
          stub_request(:get, resource_uri).to_return(
            status: 401,
            body: 'The token expired'
          )
        end

        it 'should raise an error' do
          expect do
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          end.to raise_error %r{get_token - http code: 401. Azure authentication failed: Invalid tenant_id, client_id or client_secret/certificate.}
        end
      end
    end

    context 'when getting response fails' do
      it 'should return nil if Azure returns 204' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 204,
          body: '',
          headers: {}
        )

        expect(
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        ).to be_nil
      end

      it 'should return nil if Azure returns 404' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect(
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        ).to be_nil
      end

      it 'should raise an error if other status code returns' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 400,
          body: '{"foo":"bar"}',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/http_get - http code: 400. Error message: {"foo":"bar"}/)
      end
    end
  end

  describe '#get_resource_group' do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}" }
    let(:group_api_version) { AZURE_RESOURCE_PROVIDER_GROUP }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{group_api_version}" }
    let(:response_body) do
      {
        'id' => 'fake-id',
        'name' => 'fake-name',
        'location' => 'fake-location',
        'tags' => 'fake-tags',
        'properties' => {
          'provisioningState' => 'fake-state'
        }
      }.to_json
    end
    let(:fake_resource_group) do
      {
        id: 'fake-id',
        name: 'fake-name',
        location: 'fake-location',
        tags: 'fake-tags',
        provisioning_state: 'fake-state'
      }
    end

    context 'when token is valid' do
      context 'getting response succeeds' do
        it 'should return null if response body is null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect(
            azure_client.get_resource_group(resource_group)
          ).to be_nil
        end

        it 'should return the resource if response body is not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: response_body,
            headers: {}
          )
          expect(
            azure_client.get_resource_group(resource_group)
          ).to eq(fake_resource_group)
        end
      end

      context 'getting response fails for EOFError but retry returns 200' do
        it 'should return not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri)
            .to_raise(EOFError.new).then
            .to_return(
              status: 200,
              body: response_body,
              headers: {}
            )

          expect(azure_client).to receive(:sleep).once
          expect(
            azure_client.get_resource_group(resource_group)
          ).to eq(fake_resource_group)
        end
      end
    end
  end

  describe 'get_max_fault_domains_for_location' do
    let(:url) { "/subscriptions/#{subscription_id}/providers/Microsoft.Compute/skus" }
    let(:compute_api_version) { AZURE_RESOURCE_PROVIDER_COMPUTE }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{compute_api_version}#{query_params}" }
    let(:query_params) { "&$filter=location%20eq%20'#{location}'" }
    let(:location) { 'eastus' }
    let(:max_fault_domains) { 3 }
    let(:response_body) do
      {
        'value' => [
          {
            'capabilities' => [
              {
                'name' => 'MaximumPlatformFaultDomainCount',
                'value' => max_fault_domains.to_s
              }
            ],
            'locations' => [location.upcase],
            'name' => 'Aligned',
            'resourceType' => 'availabilitySets'
          }
        ]
      }.to_json
    end

    before do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
      stub_request(:get, resource_uri).to_return(
        status: 200,
        body: response_body,
        headers: {}
      )
    end

    it 'returns the max fault domains for the provided location' do
      expect(
        azure_client.get_max_fault_domains_for_location(location)
      ).to eq(max_fault_domains)
    end

    context 'when response does not include Aligned sku' do
      let(:response_body) do
        { 'value' => [] }.to_json
      end

      it 'raises an error' do
        expect do
          azure_client.get_max_fault_domains_for_location(location)
        end.to raise_error(/Unable to get maximum fault domains for location '#{location}'/)
      end
    end
  end

  describe '#get_gallery_image_version_by_tags' do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group}/resources" }
    let(:group_api_version) { AZURE_RESOURCE_PROVIDER_GROUP }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{group_api_version}#{query_params}" }
    let(:query_params) { "&$filter=tagName%20eq%20'tag1'%20and%20tagValue%20eq%20'value1'" }
    let(:location) { 'eastus' }
    let(:gallery_uri) { "https://management.azure.com/galleries/GALLERY-NAME/images/IMAGE-DEFINITION/versions/?api-version=2016-06-01" }

    before do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
      stub_request(:get, resource_uri).to_return(
        status: 200,
        body: resource_response_body.to_json,
        headers: {}
      )
      stub_request(:get, gallery_uri).to_return(
        status: 200,
        body: gallery_response_body.to_json,
        headers: {}
      )
    end

    let(:resource_response_body) do
      {
        'value' => [
          {
            'id' => '/galleries/GALLERY-NAME/images/IMAGE-DEFINITION/versions/',
            'type' => "#{Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_COMPUTE}/#{Bosh::AzureCloud::AzureClient::REST_API_GALLERIES}/#{Bosh::AzureCloud::AzureClient::REST_API_IMAGES}/versions",
          },
        ]
      }
    end

    let(:gallery_response_body) do
      {
        'id' => '/galleries/GALLERY-NAME/images/IMAGE-DEFINITION/versions/',
      }
    end

    it 'returns the gallery image hash' do
      gallery_image = azure_client.get_gallery_image_version_by_tags('GALLERY', { 'tag1' => 'value1' })
      expect(gallery_image).to match(hash_including({
        id: '/galleries/GALLERY-NAME/images/IMAGE-DEFINITION/versions/',
        gallery_name: 'GALLERY-NAME',
        image_definition: 'IMAGE-DEFINITION',
      }))
    end

    context 'when the API response is missing value' do
      let(:resource_response_body) { {} }

      it 'returns nil' do
        gallery_image = azure_client.get_gallery_image_version_by_tags('GALLERY', { 'tag1' => 'value1' })
        expect(gallery_image).to be_nil
      end
    end

    context 'when the API response is an empty array' do
      let(:resource_response_body) { { 'value' => [] } }

      it 'returns nil' do
        gallery_image = azure_client.get_gallery_image_version_by_tags('GALLERY', { 'tag1' => 'value1' })
        expect(gallery_image).to be_nil
      end
    end
  end

  describe '#list_resource_skus' do
    let(:resource_skus_response) do
      {
        'value' => [
          {
            'resourceType' => 'virtualMachines',
            'name' => 'Standard_D2_v3',
            'tier' => 'Standard',
            'size' => 'D2_v3',
            'family' => 'D',
            'locations' => ['westus'],
            'capabilities' => [
              {
                'name' => 'MaximumPlatformFaultDomainCount',
                'value' => '2'
              },
              {
                'name' => 'MaxResourceVolumeMB',
                'value' => '51200'
              },
              {
                'name' => 'PremiumIO',
                'value' => 'False'
              }
            ]
          },
          {
            'resourceType' => 'virtualMachines',
            'name' => 'Standard_F2',
            'tier' => 'Standard',
            'size' => 'F2',
            'family' => 'F',
            'locations' => ['eastus'],
            'capabilities' => [
              {
                'name' => 'MaximumPlatformFaultDomainCount',
                'value' => '3'
              }
            ]
          },
          {
            'resourceType' => 'availabilitySets',
            'name' => 'Aligned',
            'tier' => 'Standard',
            'locations' => ['westus'],
            'capabilities' => [
              {
                'name' => 'MaximumPlatformFaultDomainCount',
                'value' => '3'
              }
            ]
          }
        ]
      }
    end
    let(:resource_skus_url) { "/subscriptions/#{subscription_id}/providers/#{Bosh::AzureCloud::AzureClient::REST_API_PROVIDER_COMPUTE}/skus" }
    let(:compute_api_version) { AZURE_RESOURCE_PROVIDER_COMPUTE }
    let(:resource_uri) { "https://management.azure.com#{resource_skus_url}?api-version=#{compute_api_version}" }

    before do
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: {
          'access_token' => valid_access_token,
          'expires_on' => expires_on
        }.to_json,
        headers: {}
      )
    end

    context 'when location is not specified' do
      it 'returns all virtual machines SKUs' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: resource_skus_response.to_json,
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus(nil, 'virtualMachines')

        expect(resource_skus.length).to eq(2)
        expect(resource_skus[0][:name]).to eq('Standard_D2_v3')
        expect(resource_skus[0][:resource_type]).to eq('virtualMachines')
        expect(resource_skus[0][:tier]).to eq('Standard')
        expect(resource_skus[0][:size]).to eq('D2_v3')
        expect(resource_skus[0][:family]).to eq('D')
        expect(resource_skus[0][:location]).to eq('westus')
        expect(resource_skus[0][:capabilities][:MaximumPlatformFaultDomainCount]).to eq('2')
        expect(resource_skus[0][:capabilities][:MaxResourceVolumeMB]).to eq('51200')
        expect(resource_skus[0][:capabilities][:PremiumIO]).to eq('False')

        expect(resource_skus[1][:name]).to eq('Standard_F2')
        expect(resource_skus[1][:capabilities][:MaximumPlatformFaultDomainCount]).to eq('3')
      end
    end

    context 'when location is specified' do
      let(:location) { 'westus' }
      let(:resource_uri) { "https://management.azure.com#{resource_skus_url}?api-version=#{compute_api_version}&$filter=location%20eq%20'#{location}'" }

      it 'filters SKUs by location' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: resource_skus_response.to_json,
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus(location, nil)

        expect(resource_skus.length).to eq(2)
        expect(resource_skus.all? { |sku| sku[:location] == location }).to be_truthy
      end
    end

    context 'when resource type is specified' do
      let(:resource_type) { 'availabilitySets' }

      it 'filters SKUs by resource type' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: resource_skus_response.to_json,
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus(nil, resource_type)

        expect(resource_skus.length).to eq(1)
        expect(resource_skus.all? { |sku| sku[:resource_type] == resource_type }).to be_truthy
      end
    end

    context 'when both location and resource type are specified' do
      let(:location) { 'westus' }
      let(:resource_uri) { "https://management.azure.com#{resource_skus_url}?api-version=#{compute_api_version}&$filter=location%20eq%20'#{location}'" }
      let(:resource_type) { 'availabilitySets' }

      it 'filters SKUs by both location and resource type' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: resource_skus_response.to_json,
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus(location, resource_type)

        expect(resource_skus.length).to eq(1)
        expect(resource_skus[0][:name]).to eq('Aligned')
        expect(resource_skus[0][:resource_type]).to eq('availabilitySets')
        expect(resource_skus[0][:location]).to eq('westus')
      end
    end

    context 'when API returns no value' do
      let(:empty_response) { { 'value' => [] } }

      it 'returns an empty array' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: empty_response.to_json,
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus

        expect(resource_skus).to be_empty
      end
    end

    context 'when API returns nil' do
      it 'returns an empty array' do
        stub_request(:get, resource_uri)
          .to_return(
            status: 200,
            body: 'null',
            headers: {}
          )

        resource_skus = azure_client.list_resource_skus

        expect(resource_skus).to be_empty
      end
    end
  end

  describe '#list_vm_skus' do
    let(:location) { 'westus' }
    let(:resource_type) { Bosh::AzureCloud::AzureClient::REST_API_VIRTUAL_MACHINES }

    it 'returns only VM SKUs' do
      allow(azure_client).to receive(:list_resource_skus).with(location, resource_type)
      azure_client.list_vm_skus(location)
      expect(azure_client).to have_received(:list_resource_skus).with(location, resource_type)
    end
  end
end
