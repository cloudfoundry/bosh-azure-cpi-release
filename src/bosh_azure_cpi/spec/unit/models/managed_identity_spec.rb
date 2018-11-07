# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::ManagedIdentity do
  let(:resource_group_name) { 'fake_resource_group' }
  let(:user_assigned_identity_name) { 'fake_identity_name' }

  context 'when system assigned managed identity is specified' do
    let(:type) { Bosh::AzureCloud::Helpers::MANAGED_IDENTITY_TYPE_SYSTEM_ASSIGNED }
    let(:config_hash) do
      {
        'type' => type
      }
    end

    it 'should configure managed identity correctly' do
      managed_identity = Bosh::AzureCloud::ManagedIdentity.new(config_hash)
      expect(managed_identity.type).to eq(type)
      expect(managed_identity.user_assigned_identity_name).to be_nil
    end

    context 'when user_assigned_identity_name is specified' do
      let(:config_hash) do
        {
          'type' => type,
          'user_assigned_identity_name' => user_assigned_identity_name
        }
      end

      it 'should configure managed identity correctly and ignore user_assigned_identity_name' do
        managed_identity = Bosh::AzureCloud::ManagedIdentity.new(config_hash)
        expect(managed_identity.type).to eq(type)
        expect(managed_identity.user_assigned_identity_name).to be_nil
      end
    end
  end

  context 'when user assigned managed identity is specified' do
    let(:type) { Bosh::AzureCloud::Helpers::MANAGED_IDENTITY_TYPE_USER_ASSIGNED }
    let(:config_hash) do
      {
        'type' => type,
        'user_assigned_identity_name' => user_assigned_identity_name
      }
    end

    it 'should configure managed identity correctly' do
      managed_identity = Bosh::AzureCloud::ManagedIdentity.new(config_hash)
      expect(managed_identity.type).to eq(type)
      expect(managed_identity.user_assigned_identity_name).to eq(user_assigned_identity_name)
    end

    context 'when user_assigned_identity_name is not specified' do
      let(:config_hash) do
        {
          'type' => type
        }
      end

      it 'should raise an error' do
        expect { Bosh::AzureCloud::ManagedIdentity.new(config_hash) }.to raise_error(/'user_assign_identity_name' is required when 'type' is 'UserAssigned'/)
      end
    end
  end
end
