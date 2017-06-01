require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#create_stemcell' do
    let(:stemcell_id) { "fake-stemcell-id" }
    let(:image_path) { "fake-image-path" }

    context 'when a light stemcell is used' do
      let(:stemcell_properties) { { 'image' => 'fake-image' } }

      it 'should succeed' do
        expect(light_stemcell_manager).to receive(:create_stemcell).
          with(stemcell_properties).and_return(stemcell_id)

        expect(
          cloud.create_stemcell(image_path, stemcell_properties)
        ).to eq(stemcell_id)
      end
    end

    context 'when a heavy stemcell is used' do
      let(:stemcell_properties) { {} }

      context 'and use_managed_disks is false' do
        it 'should succeed' do
          expect(stemcell_manager).to receive(:create_stemcell).
            with(image_path, stemcell_properties).and_return(stemcell_id)

          expect(
            cloud.create_stemcell(image_path, stemcell_properties)
          ).to eq(stemcell_id)
        end
      end

      context 'and use_managed_disks is true' do
        it 'should succeed' do
          expect(stemcell_manager2).to receive(:create_stemcell).
            with(image_path, stemcell_properties).and_return(stemcell_id)

          expect(
            managed_cloud.create_stemcell(image_path, stemcell_properties)
          ).to eq(stemcell_id)
        end
      end
    end
  end
end
