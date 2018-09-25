# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMSSInstanceId do
  describe '#self.create' do
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:agent_id) { 'fake-agent-id' }
    let(:vmss_name) { 'fake-vmss-name' }
    let(:vmss_instance_id) { '1' }
    context 'everything is ok' do
      it 'should not raise error' do
        expect do
          Bosh::AzureCloud::VMSSInstanceId.create(resource_group_name, agent_id, vmss_name, vmss_instance_id)
        end.not_to raise_error
      end
    end
  end

  describe '#self.create_from_hash' do
    let(:resource_group_name) { 'fake-resource-group-name' }
    let(:agent_id) { 'fake-agent-id' }
    let(:vmss_name) { 'fake-vmss-name' }
    let(:vmss_instance_id) { '1' }
    context 'when create instance with plain id' do
      it 'should raise error' do
        expect do
          Bosh::AzureCloud::VMSSInstanceId.create_from_hash({}, '')
        end.to raise_error /do not support plain_id in vmss instance i/
      end
    end

    context 'when everything ok' do
      it 'should not raise error' do
        expect do
          Bosh::AzureCloud::VMSSInstanceId.create_from_hash({}, nil)
        end.not_to raise_error
      end
    end
  end
end
