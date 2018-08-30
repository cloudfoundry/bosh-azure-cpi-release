# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#calculate_vm_cloud_properties' do
    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('calculate_vm_cloud_properties').and_call_original
    end

    context 'when the location is not specified in the global configuration' do
      it 'should raise an error' do
        expect do
          cloud.calculate_vm_cloud_properties({})
        end.to raise_error(/Missing the property 'location' in the global configuration/)
      end
    end

    context 'when the location is specified in the global configuration' do
      let(:location) { 'fake-location' }
      let(:cloud_properties_with_location) { mock_cloud_properties_merge('azure' => { 'location' => location }) }
      let(:cloud_with_location) { mock_cloud(cloud_properties_with_location) }

      context 'when some keys are missing in desired_instance_size' do
        let(:desired_instance_size) do
          {
            'cpu' => 1
          }
        end

        it 'should raise an error' do
          expect do
            cloud_with_location.calculate_vm_cloud_properties(desired_instance_size)
          end.to raise_error(/Missing VM cloud properties: 'ram', 'ephemeral_disk_size'/)
        end
      end

      context 'when all the keys are provided' do
        let(:size_in_gb) { 100 }
        let(:available_vm_sizes) { double('vm-sizes') }
        let(:instance_types) { double('instance-types') }

        context 'when the ephemeral_disk_size is N * 1024' do
          let(:desired_instance_size) do
            {
              'cpu' => 1,
              'ram' => 1024,
              'ephemeral_disk_size' => size_in_gb * 1024
            }
          end
          it 'should return the cloud_properties' do
            expect(azure_client).to receive(:list_available_virtual_machine_sizes_by_location).with(location).and_return(available_vm_sizes)
            expect(instance_type_mapper).to receive(:map)
              .with(desired_instance_size, available_vm_sizes)
              .and_return(instance_types)
            expect(cloud_with_location.calculate_vm_cloud_properties(desired_instance_size)).to eq(
              'instance_types' => instance_types,
              'ephemeral_disk' => {
                'size' => size_in_gb * 1024
              }
            )
          end
        end

        context 'when the ephemeral_disk_size is not N * 1024' do
          let(:desired_instance_size) do
            {
              'cpu' => 1,
              'ram' => 1024,
              'ephemeral_disk_size' => size_in_gb * 1024 + 1
            }
          end
          it 'should return the cloud_properties' do
            expect(azure_client).to receive(:list_available_virtual_machine_sizes_by_location).with(location).and_return(available_vm_sizes)
            expect(instance_type_mapper).to receive(:map)
              .with(desired_instance_size, available_vm_sizes)
              .and_return(instance_types)
            expect(cloud_with_location.calculate_vm_cloud_properties(desired_instance_size)).to eq(
              'instance_types' => instance_types,
              'ephemeral_disk' => {
                'size' => (size_in_gb + 1) * 1024
              }
            )
          end
        end
      end
    end
  end
end
