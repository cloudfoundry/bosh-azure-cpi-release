require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#delete_stemcell' do
    context 'when a light stemcell is used' do
      let(:stemcell_id) { "bosh-light-stemcell-xxx" }

      it 'should succeed' do
        expect(light_stemcell_manager).to receive(:delete_stemcell).
          with(stemcell_id)

        expect {
          cloud.delete_stemcell(stemcell_id)
        }.not_to raise_error
      end
    end

    context 'when a heavy stemcell is used' do
      let(:stemcell_id) { "bosh-stemcell-xxx" }

      context 'and use_managed_disks is false' do
        it 'should succeed' do
          expect(stemcell_manager).to receive(:delete_stemcell).
            with(stemcell_id)

          expect {
            cloud.delete_stemcell(stemcell_id)
          }.not_to raise_error
        end
      end

      context 'and use_managed_disks is true' do
        it 'should succeed' do
          expect(stemcell_manager2).to receive(:delete_stemcell).
            with(stemcell_id)

          expect {
            managed_cloud.delete_stemcell(stemcell_id)
          }.not_to raise_error
        end
      end
    end
  end
end
