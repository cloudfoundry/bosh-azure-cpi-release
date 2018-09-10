# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMSSInstanceId do
  describe '#self.parse' do
    context 'when parse vmss instance id' do
      let(:default_resource_group_name) { 'g' }
      let(:id_str) { 'resource_group_name:rg;agent_id:a;vmss_name:v;vmss_instance_id:0' }
      it 'should not raise error' do
        expect do
          vmss_id = Bosh::AzureCloud::InstanceIdParser.parse(id_str, default_resource_group_name)
          expect(vmss_id.vmss_name).to eq('v')
          expect(vmss_id.vmss_instance_id).to eq('0')
          expect(vmss_id.use_managed_disks?).to eq(true)
          vmss_id.validate
          expect(vmss_id.to_s).to eq('agent_id:a;resource_group_name:rg;vmss_instance_id:0;vmss_name:v')
        end.not_to raise_error
      end
    end
  end
end
