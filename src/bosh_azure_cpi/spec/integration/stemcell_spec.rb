# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @stemcell_path = ENV.fetch('BOSH_AZURE_STEMCELL_PATH')
  end

  describe '#stemcell' do
    context 'with heavy stemcell', heavy_stemcell: true do
      let(:extract_path)               { '/tmp/with-heavy-stemcell' }
      let(:image_path)                 { "#{extract_path}/image" }
      let(:image_metadata_path)        { "#{extract_path}/stemcell.MF" }

      before do
        FileUtils.mkdir_p(extract_path)
        run_command("tar -zxf #{@stemcell_path} -C #{extract_path}")
      end

      after do
        FileUtils.remove_dir(extract_path)
      end

      it 'should create/delete the stemcell' do
        stemcell_properties = YAML.load_file(image_metadata_path)['cloud_properties']
        heavy_stemcell_id = @cpi.create_stemcell(image_path, stemcell_properties)
        expect(heavy_stemcell_id).not_to be_nil
        @cpi.delete_stemcell(heavy_stemcell_id)
      end
    end

    context 'with light stemcell', light_stemcell: true do
      let(:extract_path)               { '/tmp/with-light-stemcell' }
      let(:image_path)                 { "#{extract_path}/image" }
      let(:image_metadata_path)        { "#{extract_path}/stemcell.MF" }

      before do
        FileUtils.mkdir_p(extract_path)
        run_command("tar -zxf #{@stemcell_path} -C #{extract_path}")
      end

      after do
        FileUtils.remove_dir(extract_path)
      end

      it 'should create/delete the stemcell' do
        stemcell_properties = YAML.load_file(image_metadata_path)['cloud_properties']
        light_stemcell_id = @cpi.create_stemcell(image_path, stemcell_properties)
        expect(light_stemcell_id).not_to be_nil
        @cpi.delete_stemcell(light_stemcell_id)
      end
    end
  end
end
