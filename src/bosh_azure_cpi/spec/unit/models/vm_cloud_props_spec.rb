# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::VMCloudProps do
  include_context 'shared stuff'
  describe '#initialize' do
    context 'when availability_set is a hash' do
      let(:av_set_name) { 'fake_av_set_name' }
      let(:platform_update_domain_count) { 5 }
      let(:platform_fault_domain_count) { 1 }
      let(:vm_cloud_props) do
        Bosh::AzureCloud::VMCloudProps.new(
          {
            'instance_type' => 'Standard_D1',
            'availability_set' => {
              'name' => av_set_name,
              'platform_update_domain_count' => platform_update_domain_count,
              'platform_fault_domain_count' => platform_fault_domain_count
            },
            'platform_update_domain_count' => 4,
            'platform_fault_domain_count' => 1
          }, azure_config_managed
        )
      end

      it 'should return the correct config' do
        expect(vm_cloud_props.availability_set.name).to eq(av_set_name)
        expect(vm_cloud_props.availability_set.platform_update_domain_count).to eq(platform_update_domain_count)
        expect(vm_cloud_props.availability_set.platform_fault_domain_count).to eq(platform_fault_domain_count)
      end
    end

    context 'when load_balancer is a hash' do
      let(:lb_name) { 'fake_lb_name' }
      let(:resource_group_name) { 'fake_resource_group' }
      context 'when resource group not empty' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'load_balancer' => {
                'name' => lb_name,
                'resource_group_name' => resource_group_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.load_balancer.name).to eq(lb_name)
          expect(vm_cloud_props.load_balancer.resource_group_name).to eq(resource_group_name)
        end
      end

      context 'when resource group empty' do
        let(:vm_cloud_props) do
          Bosh::AzureCloud::VMCloudProps.new(
            {
              'instance_type' => 'Standard_D1',
              'load_balancer' => {
                'name' => lb_name
              }
            }, azure_config_managed
          )
        end

        it 'should return the correct config' do
          expect(vm_cloud_props.load_balancer.name).to eq(lb_name)
          expect(vm_cloud_props.load_balancer.resource_group_name).to eq(azure_config_managed.resource_group_name)
        end
      end
    end
  end
end
