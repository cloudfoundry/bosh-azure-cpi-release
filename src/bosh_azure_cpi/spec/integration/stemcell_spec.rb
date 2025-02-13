# frozen_string_literal: true

require 'integration/spec_helper'

describe Bosh::AzureCloud::Cloud do
  before(:all) do
    @stemcell_path = ENV.fetch('BOSH_AZURE_STEMCELL_PATH')
    @compute_gallery_name = ENV.fetch('BOSH_AZURE_COMPUTE_GALLERY_NAME')
  end

  subject(:cpi_gallery) do
    gallery_enabled_options = @cloud_options.dup
    gallery_enabled_options['azure']['compute_gallery_name'] = @compute_gallery_name
    gallery_enabled_options['azure']['compute_gallery_replicas'] = 1
    gallery_enabled_options['azure']['use_managed_disks'] = true
    described_class.new(gallery_enabled_options, Bosh::AzureCloud::Cloud::CURRENT_API_VERSION)
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

      context 'when compute gallery is configured' do
        let(:azure_client) { Bosh::AzureCloud::AzureClient.new(cpi_gallery.config.azure, @logger) }

        before(:each) do
          @stemcell_id = nil
        end

        after(:each) do
          if @stemcell_id
            begin
              cpi_gallery.delete_stemcell(@stemcell_id)
            rescue => e
              @logger.info("Failed to clean up stemcell #{@stemcell_id}: #{e.inspect}")
            end
          else
            @logger.info('No stemcell to clean up')
          end
        end

        it 'should create gallery image definition and version' do
          stemcell_properties = YAML.load_file(image_metadata_path)['cloud_properties']
          @stemcell_id = cpi_gallery.create_stemcell(image_path, stemcell_properties)
          expect(@stemcell_id).not_to be_nil

          # Verify gallery image version was created
          stemcell_info = cpi_gallery.stemcell_manager2.get_user_image_info(@stemcell_id, 'Standard_LRS', @azure_config.location)
          expect(stemcell_info).not_to be_nil
          expect(stemcell_info.is_light_stemcell?).to be_falsey
          expect(stemcell_info.uri).to include "/Microsoft.Compute/galleries/#{@compute_gallery_name}/images/"
          image_data = JSON.parse(stemcell_info.image)
          expect(image_data['offer']).to eq stemcell_properties['os_distro']

          # Replicate image into other location
          other_location = ['eastus', 'East US'].include?(@azure_config.location) ? 'West US' : 'East US'
          cpi_gallery.stemcell_manager2.get_user_image_info(@stemcell_id, 'Standard_LRS', other_location)

          # Verify image replication
          gallery_image = azure_client.get_gallery_image_version_by_tags(@compute_gallery_name, {'stemcell_name' => @stemcell_id})
          expect(gallery_image).not_to be_nil
          expect(gallery_image[:replica_count]).to eq(1)
          actual_regions = gallery_image[:target_regions].map { |region| region.downcase.gsub(' ', '') }
          expected_regions = [@azure_config.location, other_location].map { |region| region.downcase.gsub(' ', '') }
          expect(actual_regions).to match_array(expected_regions)

          # Clean up
          cpi_gallery.delete_stemcell(@stemcell_id)

          # Verify gallery image version was deleted
          deleted_image = azure_client.get_gallery_image_version_by_tags(@compute_gallery_name, {'stemcell_name' => @stemcell_id})
          expect(deleted_image).to be_nil
          @stemcell_id = nil
        end
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
