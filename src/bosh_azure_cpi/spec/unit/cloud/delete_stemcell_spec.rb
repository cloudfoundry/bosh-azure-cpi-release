# frozen_string_literal: true

require 'spec_helper'
require 'unit/cloud/shared_stuff.rb'

describe Bosh::AzureCloud::Cloud do
  include_context 'shared stuff'

  describe '#delete_stemcell' do
    before do
      allow(telemetry_manager).to receive(:monitor)
        .with('delete_stemcell', id: stemcell_cid).and_call_original
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
    end
  end
end
