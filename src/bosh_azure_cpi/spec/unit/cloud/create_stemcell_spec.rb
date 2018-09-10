# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#create_stemcell' do
    let(:image_path) { 'fake-image-path' }
    let(:stemcell_cid) { 'fake-stemcell-cid' }

    context 'when a light stemcell is used' do
      let(:cloud_properties) { { 'image' => 'fake-image' } }

      it 'should succeed' do
        expect(telemetry_manager).to receive(:monitor)
          .with('create_stemcell', extras: { 'stemcell' => 'unknown_name-unknown_version' })
          .and_call_original

        expect(light_stemcell_manager).to receive(:create_stemcell)
          .with(cloud_properties).and_return(stemcell_cid)

        expect(
          cloud.create_stemcell(image_path, cloud_properties)
        ).to eq(stemcell_cid)
      end
    end

    context 'when a heavy stemcell is used' do
      let(:cloud_properties) { {} }

      context 'and use_managed_disks is false' do
        it 'should succeed' do
          expect(telemetry_manager).to receive(:monitor)
            .with('create_stemcell', extras: { 'stemcell' => 'unknown_name-unknown_version' })
            .and_call_original

          expect(stemcell_manager).to receive(:create_stemcell)
            .with(image_path, cloud_properties).and_return(stemcell_cid)

          expect(
            cloud.create_stemcell(image_path, cloud_properties)
          ).to eq(stemcell_cid)
        end
      end

      context 'and use_managed_disks is true' do
        it 'should succeed' do
          expect(telemetry_manager).to receive(:monitor)
            .with('create_stemcell', extras: { 'stemcell' => 'unknown_name-unknown_version' })
            .and_call_original

          expect(stemcell_manager2).to receive(:create_stemcell)
            .with(image_path, cloud_properties).and_return(stemcell_cid)

          expect(
            managed_cloud.create_stemcell(image_path, cloud_properties)
          ).to eq(stemcell_cid)
        end
      end
    end

    context 'when a stcmell name ane version are specified in cloud_properties' do
      let(:stemcell_name) { 'fake-name' }
      let(:stemcell_version) { 'fake-version' }
      let(:cloud_properties) do
        {
          'name' => stemcell_name,
          'version' => stemcell_version
        }
      end

      it 'should pass the correct stemcell info to telemetry' do
        expect(telemetry_manager).to receive(:monitor)
          .with('create_stemcell', extras: { 'stemcell' => "#{stemcell_name}-#{stemcell_version}" })
          .and_call_original

        expect(stemcell_manager).to receive(:create_stemcell)
          .with(image_path, cloud_properties).and_return(stemcell_cid)

        expect(
          cloud.create_stemcell(image_path, cloud_properties)
        ).to eq(stemcell_cid)
      end
    end
  end
end
