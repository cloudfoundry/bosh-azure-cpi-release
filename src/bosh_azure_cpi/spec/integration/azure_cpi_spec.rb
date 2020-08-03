# frozen_string_literal: true

require 'integration/spec_helper'
require 'English'
require 'json'
require 'tempfile'
require 'yaml'

describe 'the azure_cpi executable', azure_cpi_executable: true do
  before(:all) do
    @certificate = ENV.fetch('BOSH_AZURE_CERTIFICATE')
  end

  before(:each) do
    config_file.write(cloud_properties.to_yaml)
    config_file.close
  end

  let(:config_file) { Tempfile.new('cloud_properties.yml') }

  context 'when given valid credentials' do
    context 'when using service principal with password (client_secret)' do
      let(:cloud_properties) do
        {
          'cloud' => {
            'properties' => {
              'azure' => {
                'environment' => @azure_environment,
                'subscription_id' => @subscription_id,
                'resource_group_name' => @default_resource_group_name,
                'tenant_id' => @tenant_id,
                'client_id' => @client_id,
                'client_secret' => @client_secret,
                'ssh_user' => 'vcap',
                'ssh_public_key' => @ssh_public_key,
                'default_security_group' => @default_security_group,
                'parallel_upload_thread_num' => 16,
                'use_managed_disks' => true
              },
              'registry' => {
                'endpoint' => 'fake',
                'user' => 'fake',
                'password' => 'fake'
              }
            }
          }
        }
      end

      it 'should call Azure management endpoint with a valid access token' do
        result = run_cpi('method' => 'has_vm', 'arguments' => [SecureRandom.uuid.to_s], 'context' => { 'director_uuid' => 'abc123' })
        expect(result.keys).to eq(%w[result error log])
        expect(result['result']).to be_falsey
        expect(result['error']).to be_nil
      end
    end

    context 'when using service principal with certificate' do
      let(:cloud_properties) do
        {
          'cloud' => {
            'properties' => {
              'azure' => {
                'environment' => @azure_environment,
                'subscription_id' => @subscription_id,
                'resource_group_name' => @default_resource_group_name,
                'tenant_id' => @tenant_id,
                'client_id' => @client_id,
                'ssh_user' => 'vcap',
                'ssh_public_key' => @ssh_public_key,
                'default_security_group' => @default_security_group,
                'parallel_upload_thread_num' => 16,
                'use_managed_disks' => true
              },
              'registry' => {
                'endpoint' => 'fake',
                'user' => 'fake',
                'password' => 'fake'
              }
            }
          }
        }
      end

      let(:config_dir) { '/var/vcap/jobs/azure_cpi/config' }
      let(:certificate_path) { "#{config_dir}/service_principal_certificate.pem" }
      before(:each) do
        FileUtils.mkdir_p(config_dir)
        File.open(certificate_path, 'wb') do |f|
          f.write(@certificate)
        end
      end

      it 'should call Azure management endpoint with a valid access token' do
        result = run_cpi('method' => 'has_vm', 'arguments' => [SecureRandom.uuid.to_s], 'context' => { 'director_uuid' => 'abc123' })
        expect(result.keys).to eq(%w[result error log])
        expect(result['result']).to be_falsey
        expect(result['error']).to be_nil
      end
    end
  end

  context 'when given invalid credentials' do
    context 'when client_id is invalid' do
      let(:cloud_properties) do
        {
          'cloud' => {
            'properties' => {
              'azure' => {
                'environment' => @azure_environment,
                'subscription_id' => @subscription_id,
                'resource_group_name' => @default_resource_group_name,
                'tenant_id' => @tenant_id,
                'client_id' => 'fake-client-id',
                'client_secret' => @client_secret,
                'ssh_user' => 'vcap',
                'ssh_public_key' => @ssh_public_key,
                'default_security_group' => @default_security_group,
                'parallel_upload_thread_num' => 16,
                'use_managed_disks' => true
              },
              'registry' => {
                'endpoint' => 'fake',
                'user' => 'fake',
                'password' => 'fake'
              }
            }
          }
        }
      end

      it 'will not evaluate anything that causes an exception and will return the proper message to stdout' do
        result = run_cpi('method' => 'has_vm', 'arguments' => [SecureRandom.uuid.to_s], 'context' => { 'director_uuid' => 'abc123' })
        expect(result.keys).to eq(%w[result error log])
        expect(result['result']).to be_nil
        expect(result['error']['message']).to match(%r{http code: 400. Azure authentication failed: Bad request. Please assure no typo in values of tenant_id, client_id or client_secret\/certificate})
        expect(result['error']['ok_to_retry']).to be(false)
        expect(result['error']['type']).to eq('Bosh::AzureCloud::AzureError')
        expect(result['log']).to include('backtrace')
      end
    end

    context 'when client_secret is invalid' do
      let(:cloud_properties) do
        {
          'cloud' => {
            'properties' => {
              'azure' => {
                'environment' => @azure_environment,
                'subscription_id' => @subscription_id,
                'resource_group_name' => @default_resource_group_name,
                'tenant_id' => @tenant_id,
                'client_id' => @client_id,
                'client_secret' => 'fake-client-secret',
                'ssh_user' => 'vcap',
                'ssh_public_key' => @ssh_public_key,
                'default_security_group' => @default_security_group,
                'parallel_upload_thread_num' => 16,
                'use_managed_disks' => true
              },
              'registry' => {
                'endpoint' => 'fake',
                'user' => 'fake',
                'password' => 'fake'
              }
            }
          }
        }
      end

      it 'will not evaluate anything that causes an exception and will return the proper message to stdout' do
        result = run_cpi('method' => 'has_vm', 'arguments' => [SecureRandom.uuid.to_s], 'context' => { 'director_uuid' => 'abc123' })
        expect(result.keys).to eq(%w[result error log])
        expect(result['result']).to be_nil
        expect(result['error']['message']).to match(%r{http code: 401. Azure authentication failed: Invalid tenant_id, client_id or client_secret\/certificate})
        expect(result['error']['ok_to_retry']).to be(false)
        expect(result['error']['type']).to eq('Bosh::AzureCloud::AzureError')
        expect(result['log']).to include('backtrace')
      end
    end
  end

  context 'when given an empty config file' do
    let(:cloud_properties) { {} }

    it 'will return an appropriate error message when passed an invalid config file' do
      result = run_cpi('method' => 'ping', 'arguments' => [], 'context' => { 'director_uuid' => 'abc123' })
      expect(result.keys).to eq(%w[result error log])
      expect(result['result']).to be_nil
      expect(result['error']).to eq(
        'type' => 'Unknown',
        'message' => 'Could not find cloud properties in the configuration',
        'ok_to_retry' => false
      )
      expect(result['log']).to include('backtrace')
    end
  end

  context 'when given cpi config in the context' do
    let(:cloud_properties) do
      {
        'cloud' => {
          'properties' => {
            'azure' => {
            },
            'registry' => {
              'endpoint' => 'fake',
              'user' => 'fake',
              'password' => 'fake'
            }
          }
        }
      }
    end
    let(:context) do
      {
        'request_id' => 'abc123',
        'director_uuid' => 'abc123',
        'environment' => @azure_environment,
        'subscription_id' => @subscription_id,
        'resource_group_name' => @default_resource_group_name,
        'tenant_id' => @tenant_id,
        'client_id' => @client_id,
        'client_secret' => @client_secret,
        'ssh_user' => 'vcap',
        'ssh_public_key' => @ssh_public_key,
        'default_security_group' => @default_security_group,
        'parallel_upload_thread_num' => 16,
        'use_managed_disks' => true,
      }
    end

    it 'merges the context into the cloud_properties' do
      result = run_cpi('method' => 'has_vm', 'arguments' => [SecureRandom.uuid.to_s], 'context' => context)
      expect(result.keys).to eq(%w[result error log])
      expect(result['result']).to_not be_nil
      expect(result['result']).to be_falsey
      expect(result['error']).to be_nil
    end

    it 'returns the api version' do
      result = run_cpi('method' => 'info', 'arguments' => [], 'context' => context)
      expect(result['result']).to_not be_nil
      expect(result['error']).to be_nil
      expect(result['result']['api_version']).to eq(2)
    end
  end

  def run_cpi(input)
    command_file = Tempfile.new('command.json')
    command_file.write(input.to_json)
    command_file.close

    stdoutput = `bin/azure_cpi #{config_file.path} < #{command_file.path}`
    status = $CHILD_STATUS.exitstatus

    expect(status).to eq(0)
    JSON.parse(stdoutput)
  end
end
