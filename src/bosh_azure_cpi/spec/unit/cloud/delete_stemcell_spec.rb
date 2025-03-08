# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#delete_stemcell' do
    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('delete_stemcell', { id: stemcell_cid }).and_call_original
    end

    context 'when a light stemcell is used' do
      let(:stemcell_cid) { 'bosh-light-stemcell-98cc8a2d-6e33-409a-91f5-fb32e320f5c1' }

      it 'should succeed' do
        expect(light_stemcell_manager).to receive(:delete_stemcell)
          .with(stemcell_cid)

        expect do
          cloud.delete_stemcell(stemcell_cid)
        end.not_to raise_error
      end

      context 'and compute_gallery is enabled' do
        let(:compute_gallery_cloud) { mock_cloud(mock_cloud_properties_merge({'azure' => {'compute_gallery_name' => 'gallery-name', 'use_managed_disks' => true}})) }

        it 'should still use the light stemcell manager' do
          expect(light_stemcell_manager).to receive(:delete_stemcell)
            .with(stemcell_cid)
          expect(stemcell_manager).not_to receive(:delete_stemcell)
          expect(stemcell_manager2).not_to receive(:delete_stemcell)

          expect do
            compute_gallery_cloud.delete_stemcell(stemcell_cid)
          end.not_to raise_error
        end
      end
    end

    context 'when a heavy stemcell is used' do
      let(:stemcell_cid) { 'bosh-stemcell-eb365f8d-c069-4795-a6fc-3fb93dee6f0c' }

      context 'and use_managed_disks is false' do
        it 'should succeed' do
          expect(stemcell_manager).to receive(:delete_stemcell)
            .with(stemcell_cid)

          expect do
            cloud.delete_stemcell(stemcell_cid)
          end.not_to raise_error
        end
      end

      context 'and use_managed_disks is true' do
        it 'should succeed' do
          expect(stemcell_manager2).to receive(:delete_stemcell)
            .with(stemcell_cid)

          expect do
            managed_cloud.delete_stemcell(stemcell_cid)
          end.not_to raise_error
        end
      end

      context 'and compute_gallery is enabled' do
        let(:compute_gallery_cloud) { mock_cloud(mock_cloud_properties_merge({'azure' => {'compute_gallery_name' => 'gallery-name', 'use_managed_disks' => true}})) }

        it 'should use stemcell_manager2' do
          expect(stemcell_manager2).to receive(:delete_stemcell)
            .with(stemcell_cid)
          expect(light_stemcell_manager).not_to receive(:delete_stemcell)
          expect(stemcell_manager).not_to receive(:delete_stemcell)

          expect do
            compute_gallery_cloud.delete_stemcell(stemcell_cid)
          end.not_to raise_error
        end
      end
    end
  end
end
