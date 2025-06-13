# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'tmpdir'

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

  describe '#list_resource_skus' do
    let(:location) { 'eastus' }
    let(:resource_type) { 'virtualMachines' }
    let(:skus_url) { "/subscriptions/#{subscription_id}/providers/Microsoft.Compute/skus" }
    let(:skus_uri) { %r{^https://management.azure.com#{skus_url}\?api-version=.+} }
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
    let(:response_body) do
      {
        'value' => [
          { 'name' => 'Standard_D1', 'resourceType' => 'virtualMachines', 'locations' => ['eastus'], 'capabilities' => [{ 'name' => 'C1', 'value' => 'V1' }] },
          { 'name' => 'Standard_D2', 'resourceType' => 'virtualMachines', 'locations' => ['eastus'], 'capabilities' => [] },
          { 'name' => 'Basic_A0', 'resourceType' => 'virtualMachines', 'locations' => ['westus'] },
          {
            'name' => 'Standard_F2',
            'resourceType' => 'availabilitySets',
            'tier' => 'Standard',
            'size' => 'F2',
            'family' => 'F',
            'locations' => ['swedencentral'],
            'capabilities' => [
              {
                'name' => 'MaximumPlatformFaultDomainCount',
                'value' => '3'
              }
            ]
          },
        ]
      }.to_json
    end
    let(:expected_skus) do
      [
        { name: 'Standard_D1', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: { C1: 'V1' } },
        { name: 'Standard_D2', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: {} },
        { name: 'Basic_A0', resource_type: 'virtualMachines', location: 'westus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: {} },
        { name: 'Standard_F2', resource_type: 'availabilitySets', location: 'swedencentral', tier: 'Standard', size: 'F2', family: 'F', restrictions: nil, capabilities: { MaximumPlatformFaultDomainCount: '3' } }
      ]
    end
    let(:cache_file) { File.join(full_cache_dir, 'skus_all_all.json') }
    let(:tmp_cache_dir) { @tmp_cache_dir }
    let(:cache_subdir) { Bosh::AzureCloud::AzureClient::CACHE_SUBDIR }
    let(:full_cache_dir) { File.join(tmp_cache_dir, cache_subdir) }
    let(:cache_expiry) { Bosh::AzureCloud::AzureClient::CACHE_EXPIRY_SECONDS }

    before do
      @tmp_cache_dir = Dir.mktmpdir('azure-cpi-rspec-cache')
      stub_const('Bosh::AzureCloud::AzureClient::CACHE_DIR', @tmp_cache_dir)
      stub_request(:post, token_uri).to_return(
        status: 200,
        body: { 'access_token' => valid_access_token, 'expires_on' => expires_on }.to_json,
        headers: {}
      )
    end

    after do
      FileUtils.remove_entry_secure @tmp_cache_dir if @tmp_cache_dir && Dir.exist?(@tmp_cache_dir)
    end

    context 'when cache is empty' do
      before do
        stub_request(:get, skus_uri).to_return(status: 200, body: response_body, headers: {})
        expect(File).not_to exist(cache_file)
      end

      context 'when no filter is set' do
        it 'calls the API, returns the skus, and writes to cache' do
          skus = azure_client.list_resource_skus(nil, nil)

          expect(skus).to eq(expected_skus)
          expect(File).to exist(cache_file)
          expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
          expect(a_request(:get, skus_uri)).to have_been_made.once
        end
      end

      context 'when location filter is set' do
        let(:skus_uri) { %r{^https://management.azure.com#{skus_url}\?\$filter=location%20eq%20'#{location}'&api-version=.+} }
        let(:cache_file) { File.join(full_cache_dir, "skus_#{location}_all.json") }
        let(:expected_skus) do
          [
            { name: 'Standard_D1', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: { C1: 'V1' } },
            { name: 'Standard_D2', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: {} },
          ]
        end

        it 'calls the API, returns the skus, and writes to cache' do
          skus = azure_client.list_resource_skus(location)

          expect(skus).to eq(expected_skus)
          expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
          expect(a_request(:get, skus_uri)).to have_been_made.once
        end
      end

      context 'when location and resource_type filter is set' do
        let(:location) { 'swedencentral' }
        let(:resource_type) { 'availabilitySets' }
        let(:skus_uri) { %r{^https://management.azure.com#{skus_url}\?\$filter=location%20eq%20'#{location}'&api-version=.+} }
        let(:cache_file) { File.join(full_cache_dir, "skus_#{location}_#{resource_type}.json") }
        let(:expected_skus) do
          [
            { name: 'Standard_F2', resource_type: 'availabilitySets', location: 'swedencentral', tier: 'Standard', size: 'F2', family: 'F', restrictions: nil, capabilities: { MaximumPlatformFaultDomainCount: '3' } }
          ]
        end

        it 'calls the API, returns filtered skus, and writes to cache' do
          skus = azure_client.list_resource_skus(location, resource_type)

          expect(skus).to eq(expected_skus)
          expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
          expect(a_request(:get, skus_uri)).to have_been_made.once
        end
      end

      context 'when resource_type filter is set' do
        let(:cache_file) { File.join(full_cache_dir, "skus_all_#{resource_type}.json") }
        let(:expected_skus) do
          [
            { name: 'Standard_D1', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: { C1: 'V1' } },
            { name: 'Standard_D2', resource_type: 'virtualMachines', location: 'eastus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: {} },
            { name: 'Basic_A0', resource_type: 'virtualMachines', location: 'westus', tier: nil, size: nil, family: nil, restrictions: nil, capabilities: {} },
          ]
        end

        it 'calls the API with resource_type filter, returns the skus, and writes to cache' do
          skus = azure_client.list_resource_skus(nil, resource_type)

          expect(skus).to eq(expected_skus)
          expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
          expect(a_request(:get, skus_uri)).to have_been_made.once
        end
      end
    end

    context 'when cache is valid' do
      before do
        FileUtils.mkdir_p(full_cache_dir)
        File.write(cache_file, JSON.pretty_generate(expected_skus))
      end

      it 'reads from the cache and does not call the API' do
        stub_request(:get, skus_uri).to_raise(StandardError.new('API should not be called'))

        skus = azure_client.list_resource_skus()

        expect(skus).to eq(expected_skus)
        expect(a_request(:get, skus_uri)).not_to have_been_made
      end
    end

    context 'when cache is expired' do
      before do
        FileUtils.mkdir_p(full_cache_dir)
        File.write(cache_file, JSON.pretty_generate([{ name: 'old_sku' }]))
        expired_time = Time.now - cache_expiry - 60
        File.utime(expired_time, expired_time, cache_file)
      end

      it 'calls the API, returns fresh data, and updates the cache' do
        stub_request(:get, skus_uri)
          .to_return(status: 200, body: response_body, headers: {})

        skus = azure_client.list_resource_skus()

        expect(skus).to eq(expected_skus)
        expect(File).to exist(cache_file)
        expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
        # Check that the modification time is recent (within a small tolerance)
        expect(File.mtime(cache_file)).to be > (Time.now - 10)
        expect(a_request(:get, skus_uri)).to have_been_made.once
      end
    end

    context 'when cache file is corrupted' do
      before do
        FileUtils.mkdir_p(full_cache_dir)
        File.write(cache_file, 'invalid json')
      end

      it 'logs a warning, calls the API, returns fresh data, and updates the cache' do
         stub_request(:get, skus_uri).to_return(status: 200, body: response_body, headers: {})
         expect(logger).to receive(:warn).with(/Failed to parse cache file/)

         skus = azure_client.list_resource_skus()

         expect(skus).to eq(expected_skus)
         expect(File).to exist(cache_file)
         expect(JSON.parse(File.read(cache_file), symbolize_names: true)).to eq(expected_skus)
         expect(a_request(:get, skus_uri)).to have_been_made.once
      end
    end

    context 'when API returns no value' do
      let(:empty_response) { { 'value' => [] }.to_json }

      it 'returns an empty array' do
        stub_request(:get, skus_uri).to_return(status: 200, body: empty_response, headers: {})
        expect(File).not_to exist(cache_file)

        resource_skus = azure_client.list_resource_skus()

        expect(resource_skus).to be_empty
        expect(a_request(:get, skus_uri)).to have_been_made.once
      end
    end

    context 'when API returns nil body' do
      it 'returns an empty array and caches it' do
        stub_request(:get, skus_uri).to_return(status: 200, body: 'null', headers: {})
        expect(File).not_to exist(cache_file)

        resource_skus = azure_client.list_resource_skus()

        expect(resource_skus).to be_empty
        expect(a_request(:get, skus_uri)).to have_been_made.once
      end
    end

    context 'when cache parent directory does not exist' do
      it 'calls the API, returns the skus, but does not cache' do
        stub_request(:get, skus_uri).to_return(status: 200, body: response_body, headers: {})
        FileUtils.remove_entry_secure tmp_cache_dir

        skus = azure_client.list_resource_skus()

        expect(skus).to eq(expected_skus)
        expect(File).not_to exist(cache_file)
        expect(a_request(:get, skus_uri)).to have_been_made.once
      end
    end
  end

  describe '#list_vm_skus' do
    let(:location) { 'westus' }
    let(:resource_type) { Bosh::AzureCloud::AzureClient::REST_API_VIRTUAL_MACHINES }

    it 'returns only VM SKUs' do
      expect(azure_client).to receive(:list_resource_skus).with(location, resource_type)

      azure_client.list_vm_skus(location)
    end
  end
end
