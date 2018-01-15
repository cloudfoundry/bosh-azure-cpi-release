require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#calculate_vm_cloud_properties' do
    before do
      allow(telemetry_manager).to receive(:monitor).
        with('calculate_vm_cloud_properties').and_call_original
    end

    context "when the location is not specified in the global configuration" do
      it "should raise an error" do
        expect {
          cloud.calculate_vm_cloud_properties({})
        }.to raise_error(/Missing the property `location' in the global configuration/)
      end
    end

    context "when the location is specified in the global configuration" do
      let(:location) { "fake-location" }
      let(:cloud_properties_with_location) { mock_cloud_properties_merge({'azure'=>{'location'=>location}}) }
      let(:cloud_with_location) { mock_cloud(cloud_properties_with_location) }

      context "when some keys are missing in vm_resources" do
        let(:vm_resources) {
          {
            'cpu' => 1
          }
        }

        it "should raise an error" do
          expect {
            cloud_with_location.calculate_vm_cloud_properties(vm_resources)
          }.to raise_error(/Missing VM cloud properties: `ram', `ephemeral_disk_size'/)
        end
      end

      context "when all the keys are provided" do
        let(:size_in_gb) { 100 }
        let(:available_vm_sizes) { double("vm-sizes") }
        let(:instance_type) { double("instance-type") }

        context "when the ephemeral_disk_size is N * 1024" do
          let(:vm_resources) {
            {
              'cpu' => 1,
              'ram' => 1024,
              'ephemeral_disk_size' => size_in_gb * 1024
            }
          }
          it "should return the cloud_properties" do
            expect(client2).to receive(:list_available_virtual_machine_sizes).with(location).and_return(available_vm_sizes)
            expect(instance_type_mapper).to receive(:map).
              with(vm_resources, available_vm_sizes).
              and_return(instance_type)
            expect(cloud_with_location.calculate_vm_cloud_properties(vm_resources)).to eq({
              'instance_type' => instance_type,
              'ephemeral_disk' => {
                'size' => size_in_gb * 1024
              }
            })
          end
        end

        context "when the ephemeral_disk_size is not N * 1024" do
          let(:vm_resources) {
            {
              'cpu' => 1,
              'ram' => 1024,
              'ephemeral_disk_size' => size_in_gb * 1024 + 1
            }
          }
          it "should return the cloud_properties" do
            expect(client2).to receive(:list_available_virtual_machine_sizes).with(location).and_return(available_vm_sizes)
            expect(instance_type_mapper).to receive(:map).
              with(vm_resources, available_vm_sizes).
              and_return(instance_type)
            expect(cloud_with_location.calculate_vm_cloud_properties(vm_resources)).to eq({
              'instance_type' => instance_type,
              'ephemeral_disk' => {
                'size' => (size_in_gb + 1) * 1024
              }
            })
          end
        end
      end
    end
  end
end
