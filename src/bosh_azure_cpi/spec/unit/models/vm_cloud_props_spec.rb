# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VMCloudProps do
  let(:global_configurations) { instance_double('AzureConfig') }

  context 'when instance_type and instance_types are not provided' do
    let(:vm_cloud_properties) { {} }

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, global_configurations)
      end.to raise_error(/The cloud property 'instance_type' is missing. Alternatively you can specify 'vm_resources' key./)
    end
  end

  context 'when availability_zone is specified' do
    let(:vm_cloud_properties) do
      {
        'availability_zone' => 'fake-az',
        'instance_type' => 'fake-vm-size'
      }
    end
    before do
      allow(global_configurations).to receive(:use_managed_disks).and_return(false)
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, global_configurations)
      end.to raise_error('Virtual Machines deployed to an Availability Zone must use managed disks')
    end
  end

  context 'when an invalid availability_zone is specified' do
    let(:zone) { 'invalid-zone' } # valid values are '1', '2', '3'
    let(:vm_cloud_properties) do
      {
        'availability_zone' => zone,
        'instance_type' => 'c'
      }
    end
    before do
      allow(global_configurations).to receive(:use_managed_disks).and_return(true)
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, global_configurations)
      end.to raise_error /'#{zone}' is not a valid zone/
    end
  end

  context 'when both availability_zone and availability_set are specified' do
    let(:vm_cloud_properties) do
      {
        'availability_zone' => '1',
        'availability_set' => 'b',
        'instance_type' => 'c'
      }
    end
    before do
      allow(global_configurations).to receive(:use_managed_disks).and_return(true)
    end

    it 'should raise an error' do
      expect do
        Bosh::AzureCloud::VMCloudProps.new(vm_cloud_properties, global_configurations)
      end.to raise_error /Only one of 'availability_zone' and 'availability_set' is allowed to be configured for the VM but you have configured both/
    end
  end
end
