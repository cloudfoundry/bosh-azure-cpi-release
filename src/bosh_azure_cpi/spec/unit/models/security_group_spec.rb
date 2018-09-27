# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::SecurityGroup do
  let(:resource_group_name) { 'fake_resource_group' }
  let(:sg_name) { 'fake_sg_name' }
  let(:security_group_with_resource_group) do
    {
      'resource_group_name' => resource_group_name,
      'name' => sg_name
    }
  end
  describe '#self.parse_security_group' do
    context 'when resource group specified' do
      it 'the resource group value is correct' do
        security_group = Bosh::AzureCloud::SecurityGroup.parse_security_group(security_group_with_resource_group)
        expect(security_group.resource_group_name).to eq(resource_group_name)
        expect(security_group.name).to eq(sg_name)
      end
    end
  end

  describe '#to_s' do
    context 'when called' do
      let(:sg_string) { "name: #{sg_name}, resource_group_name: #{resource_group_name}" }
      it 'should return the correct string' do
        security_group = Bosh::AzureCloud::SecurityGroup.parse_security_group(security_group_with_resource_group)
        expect(security_group.to_s).to eq(sg_string)
      end
    end
  end
end
