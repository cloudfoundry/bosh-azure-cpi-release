# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::ResObjectId do
  describe '#self.parse_with_resource_group' do
    let(:plain_id) { 'mock_plain_id' }
    let(:resource_group_name) { 'mock_rg' }

    context 'when parse with resource group' do
      it 'the resource group value is correct' do
        expect do
          id_hash, plain_id_str = Bosh::AzureCloud::ResObjectId.parse_with_resource_group(plain_id, resource_group_name)
          obj_id = Bosh::AzureCloud::ResObjectId.new(id_hash, plain_id_str)
          expect(obj_id.resource_group_name).to eq(resource_group_name)
        end.not_to raise_error
      end
    end

    context 'when parse with wrong format string' do
      let(:wrong_id_str) { 'mock_plain_id;ak:av' }

      it 'should raise error' do
        ErrorMsg = Bosh::AzureCloud::ErrorMsg
        expect do
          Bosh::AzureCloud::ResObjectId.parse_with_resource_group(wrong_id_str, resource_group_name)
        end.to raise_error(/#{ErrorMsg::OBJ_ID_KEY_VALUE_FORMAT_ERROR}/)
      end
    end
  end
end
