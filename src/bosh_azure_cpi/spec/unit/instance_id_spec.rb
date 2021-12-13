# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::InstanceId do
  describe '#self.create' do
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:agent_id) { 'fake-agent-id' }

    context 'when storage_account_name is nil' do
      let(:id) do
        {
          'resource_group_name' => resource_group_name,
          'agent_id' => agent_id
        }
      end

      it 'should initialize the instance_id' do
        instance_id = Bosh::AzureCloud::InstanceId.create(resource_group_name, agent_id)
        expect(instance_id.instance_variable_get('@plain_id')).to eq(nil)
        expect(instance_id.instance_variable_get('@id_hash')).to eq(id)
      end
    end

    context 'when storage_account_name is NOT nil' do
      let(:storage_account_name) { 'fakestorageaccountname' }
      let(:id) do
        {
          'resource_group_name' => resource_group_name,
          'agent_id' => agent_id,
          'storage_account_name' => storage_account_name
        }
      end

      it 'should initialize the instance_id' do
        instance_id = Bosh::AzureCloud::InstanceId.create(resource_group_name, agent_id, storage_account_name)
        expect(instance_id.instance_variable_get('@plain_id')).to eq(nil)
        expect(instance_id.instance_variable_get('@id_hash')).to eq(id)
      end
    end
  end

  describe '#self.parse' do
    let(:default_resource_group_name) { 'default-resource-group-name' }
    let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }

    before do
      allow(instance_id).to receive(:validate)
    end

    context 'when id contains ":"' do
      let(:id) { 'a:a;b:b;agent_id:fake-agent-id' }

      it 'should initialize a v2 instance_id' do
        expect do
          instance_id = Bosh::AzureCloud::InstanceId.parse(id, default_resource_group_name)
          expect(instance_id.instance_variable_get('@plain_id')).to eq(nil)
        end.not_to raise_error
      end
    end

    context 'when id does not contain ":"' do
      let(:id) { 'i' * Bosh::AzureCloud::Helpers::UUID_LENGTH }

      it 'should initialize a v1 instance_id' do
        expect do
          instance_id = Bosh::AzureCloud::InstanceId.parse(id, default_resource_group_name)
          expect(instance_id.instance_variable_get('@plain_id')).to eq(id)
        end.not_to raise_error
      end
    end
  end

  describe '#to_s' do
    context 'when instance id is a v1 id' do
      let(:instance_id_string) { SecureRandom.uuid.to_s }
      let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'default-resource-group-name') }

      it 'should return the v1 string' do
        expect(instance_id.to_s).to eq(instance_id_string)
      end
    end

    context 'when instance id is a v2 id' do
      context 'when instance id is initialized by self.parse' do
        let(:default_resource_group_name) { 'r' }
        let(:instance_id_string) { 'agent_id:a;resource_group_name:r;storage_account_name:s' }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, default_resource_group_name) }

        it 'should return the v2 string' do
          expect(instance_id.to_s).to eq(instance_id_string)
        end
      end

      context 'when instance id is initialized by self.create' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:agent_id) { 'fake-agent-id' }
        let(:storage_account_name) { 'fakestorageaccountname' }
        let(:instance_id_string) { "agent_id:#{agent_id};resource_group_name:#{resource_group_name};storage_account_name:#{storage_account_name}" }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.create(resource_group_name, agent_id, storage_account_name) }

        it 'should return the v2 string' do
          expect(instance_id.to_s).to eq(instance_id_string)
        end
      end

      context 'when the same instance id is initialized by self.create and self.parse' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:agent_id) { 'fake-agent-id' }
        let(:storage_account_name) { 'fakestorageaccountname' }
        let(:instance_id_string) { "agent_id:#{agent_id};resource_group_name:#{resource_group_name};storage_account_name:#{storage_account_name}" }
        let(:instance_id_1) { Bosh::AzureCloud::InstanceId.create(resource_group_name, agent_id, storage_account_name) }
        let(:instance_id_2) { Bosh::AzureCloud::InstanceId.parse(instance_id_1.to_s, resource_group_name) }

        it 'should have same output string' do
          expect(instance_id_1.to_s).to eq(instance_id_2.to_s)
        end
      end
    end
  end

  describe '#resource_group_name' do
    context 'when instance id is a v1 id' do
      let(:default_resource_group_name) { 'fake-resource-group-name' }
      let(:instance_id_string) { SecureRandom.uuid.to_s }
      let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, default_resource_group_name) }

      it 'should return the default resource group' do
        expect(instance_id.resource_group_name).to eq(default_resource_group_name)
      end
    end

    context 'when instance id is a v2 id' do
      context 'when instance id contains resource_group_name' do
        let(:default_resource_group_name) { 'fake-resource-group-name' }
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:instance_id_string) { "resource_group_name:#{resource_group_name};agent_id:a;storage_account_name:s" }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, default_resource_group_name) }

        it 'should return the resource group specified in instance id' do
          expect(instance_id.resource_group_name).to eq(resource_group_name)
        end
      end
    end
  end

  describe '#vm_name' do
    context 'when instance id is a v1 id' do
      let(:instance_id_string) { "fakestorageaccountname-#{SecureRandom.uuid}" }
      let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

      it 'should return v1 id' do
        expect(instance_id.vm_name).to eq(instance_id_string)
      end
    end

    context 'when instance id is a v2 id' do
      let(:agent_id) { SecureRandom.uuid }
      let(:instance_id_string) { "resource_group_name:r;agent_id:#{agent_id};storage_account_name:s" }
      let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

      it 'should return the agent_id specified in instance id' do
        expect(instance_id.vm_name).to eq(agent_id)
      end
    end
  end

  describe '#storage_account_name' do
    context 'when instance id is a v1 id' do
      context 'when it is a managed disk vm' do
        let(:instance_id_string) { SecureRandom.uuid.to_s }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should return nil' do
          expect(instance_id.storage_account_name).to be(nil)
        end
      end

      context 'when it is a unmanaged disk vm' do
        let(:storage_account_name) { 'fakestorageaccountname' }
        let(:instance_id_string) { "#{storage_account_name}-#{SecureRandom.uuid}" }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should get storage account from v1 vm name' do
          expect(instance_id.storage_account_name).to eq(storage_account_name)
        end
      end
    end

    context 'when instance id is a v2 id' do
      let(:storage_account_name) { 'fakestorageaccountname' }
      let(:instance_id_string) { "resource_group_name:r;agent_id:None;storage_account_name:#{storage_account_name}" }
      let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

      it 'should return the storage account specified in instance id' do
        expect(instance_id.storage_account_name).to eq(storage_account_name)
      end
    end
  end

  describe 'use_managed_disks?' do
    context 'when instance id is a v1 id' do
      context 'when it is a unmanaged disk vm' do
        let(:storage_account_name) { 'fakestorageaccountname' }
        let(:instance_id_string) { "#{storage_account_name}-#{SecureRandom.uuid}" }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should return false' do
          expect(instance_id.use_managed_disks?).to be(false)
        end
      end

      context 'when it is a managed disk vm' do
        let(:instance_id_string) { SecureRandom.uuid.to_s }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should return true' do
          expect(instance_id.use_managed_disks?).to be(true)
        end
      end
    end

    context 'when instance id is a v2 id' do
      context 'when it is a unmanaged disk vm' do
        let(:instance_id_string) { 'resource_group_name:r;agent_id:None;storage_account_name:s' }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should return false' do
          expect(instance_id.use_managed_disks?).to be(false)
        end
      end

      context 'when it is a managed disk vm' do
        let(:instance_id_string) { 'resource_group_name:r;agent_id:None' }
        let(:instance_id) { Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name') }

        it 'should return true' do
          expect(instance_id.use_managed_disks?).to be(true)
        end
      end
    end
  end

  describe '#validate' do
    context 'when instance id is a v1 id' do
      context 'when it is a unmanaged disk vm and length of agent id is not 36' do
        let(:storage_account_name) { 'fakestorageaccountname' }
        let(:instance_id_string) { "#{storage_account_name}-length-not-equal-to-36" }
        let(:instance_id) {}

        it 'should raise an error' do
          expect do
            Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name')
          end.to raise_error(/Invalid instance id \(plain\)/)
        end
      end

      context 'when it is a managed disk vm and length of agent id is not 36' do
        let(:instance_id_string) { 'length-not-equal-to-36' }

        it 'should raise an error' do
          expect do
            Bosh::AzureCloud::InstanceId.parse(instance_id_string, 'fake-resource-group-name')
          end.to raise_error(/Invalid instance id \(plain\)/)
        end
      end
    end

    context 'when instance id is a v2 id' do
      context 'when validating resource_group_name' do
        context 'when it is nil' do
          let(:instance_id) { Bosh::AzureCloud::InstanceId.create(nil, 'agent-id', 'storage-account-name') }

          it 'should raise an error' do
            expect do
              instance_id.validate
            end.to raise_error(/Invalid resource_group_name in instance id \(version 2\)/)
          end
        end

        context 'when it is empty' do
          let(:instance_id) { Bosh::AzureCloud::InstanceId.create('', 'agent-id', 'storage-account-name') }

          it 'should raise an error' do
            expect do
              instance_id.validate
            end.to raise_error(/Invalid resource_group_name in instance id \(version 2\)/)
          end
        end
      end

      context 'when validating vm_name' do
        context 'when it is nil' do
          let(:instance_id) { Bosh::AzureCloud::InstanceId.create('resource-group-name', nil, 'storage-account-name') }

          it 'should raise an error' do
            expect do
              instance_id.validate
            end.to raise_error(/Invalid vm_name in instance id \(version 2\)/)
          end
        end

        context 'when it is empty' do
          let(:instance_id) { Bosh::AzureCloud::InstanceId.create('resource-group-name', '', 'storage-account-name') }

          it 'should raise an error' do
            expect do
              instance_id.validate
            end.to raise_error(/Invalid vm_name in instance id \(version 2\)/)
          end
        end
      end

      context 'when validating storage_account_name' do
        context 'when it is empty' do
          let(:instance_id) { Bosh::AzureCloud::InstanceId.create('resource-group-name', 'agent-id', '') }

          it 'should raise an error' do
            expect do
              instance_id.validate
            end.to raise_error(/Invalid storage_account_name in instance id \(version 2\)/)
          end
        end
      end
    end
  end
end
