# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::ComputeGalleryManager do
  let(:azure_config) { instance_double(Bosh::AzureCloud::AzureConfig) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:default_storage_account_name) { 'test-storage-account' }
  let(:replica_count) { 5 }
  let(:logger) { double('logger') }
  let(:gallery_name) { 'test-gallery' }
  let(:image_definition) { 'test-image-def' }
  let(:version) { '1.0.0' }
  let(:location) { 'eastus' }
  let(:stemcell_name) { 'bosh-stemcell-1234' }

  subject(:compute_gallery_manager) do
    described_class.new(azure_config, azure_client, blob_manager, default_storage_account_name)
  end

  before do
    allow(azure_config).to receive(:compute_gallery_name).and_return(gallery_name)
    allow(azure_config).to receive(:compute_gallery_replicas).and_return(replica_count)
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(compute_gallery_manager).to receive(:flock).and_yield
  end

  describe '#enabled?' do
    context 'when compute gallery name is configured' do
      before do
        allow(azure_config).to receive(:compute_gallery_name).and_return('test-gallery')
      end

      it 'returns true' do
        expect(compute_gallery_manager.enabled?).to be_truthy
      end
    end

    context 'when compute gallery name is nil' do
      before do
        allow(azure_config).to receive(:compute_gallery_name).and_return(nil)
      end

      it 'returns false' do
        expect(compute_gallery_manager.enabled?).to be_falsey
      end
    end

    context 'when compute gallery name is empty' do
      before do
        allow(azure_config).to receive(:compute_gallery_name).and_return('')
      end

      it 'returns false' do
        expect(compute_gallery_manager.enabled?).to be false
      end
    end
  end

  describe '#find_gallery_image_by_stemcell_name' do
    it 'delegates to azure client' do
      gallery_image = { id: 'test-id' }
      expect(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
        .with(gallery_name, stemcell_name)
        .and_return(gallery_image)

      result = compute_gallery_manager.find_gallery_image_by_stemcell_name(stemcell_name)
      expect(result).to eq(gallery_image)
    end
  end

  describe '#create_gallery_image' do
    let(:metadata) do
      {
        'os_type' => 'Linux',
        'generation' => 'gen1',
        'image' => '{"publisher":"bosh","offer":"test","sku":"gen1","version":"1.0.0"}',
        'image_sha256' => 'abc123',
        'architecture' => 'x86_64'
      }
    end

    context 'when gallery image does not exist' do
      before do
        allow(azure_client).to receive(:get_gallery_image_version)
          .with(gallery_name, image_definition, version)
          .and_return(nil)
        allow(azure_client).to receive(:get_gallery_image_definition)
          .with(gallery_name, image_definition)
          .and_return(nil)
        allow(azure_client).to receive(:create_gallery_image_definition)
        allow(azure_client).to receive(:create_update_gallery_image_version)
          .and_return({ id: 'new-image-id' })
        allow(blob_manager).to receive(:get_blob_uri)
          .and_return('https://storage.blob.core.windows.net/stemcells/test.vhd')
        allow(compute_gallery_manager).to receive(:flock).and_yield
      end

      it 'creates a new gallery image definition and version' do
        result = compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

        expect(azure_client).to have_received(:create_gallery_image_definition)
        expect(azure_client).to have_received(:create_update_gallery_image_version)
        expect(result[:id]).to eq('new-image-id')
      end

      context 'when image definition already exists' do
        let(:existing_definition) do
          {
            'id' => '/subscriptions/test/resourceGroups/test/providers/Microsoft.Compute/galleries/test-gallery/images/test-image-def',
            'name' => image_definition,
            'properties' => {
              'features' => [
                { 'name' => 'SecurityType', 'value' => 'TrustedLaunchSupported' }
              ]
            }
          }
        end

        before do
          allow(azure_client).to receive(:get_gallery_image_definition)
            .with(gallery_name, image_definition)
            .and_return(existing_definition)
        end

        # Skip update of existing image definition, because the compute gallery image may have features defined and
        # Azure doesn't allow modifying/removing features, so we skip the PUT if it exists.
        it 'skips image definition creation and creates image version' do
          result = compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

          expect(azure_client).not_to have_received(:create_gallery_image_definition)
          expect(azure_client).to have_received(:create_update_gallery_image_version)
          expect(result[:id]).to eq('new-image-id')
        end
      end

      context 'when create_gallery_image_definition fails' do
        before do
          allow(azure_client).to receive(:create_gallery_image_definition)
            .and_raise('Failed to create gallery image definition')
        end

        it 'raises an error' do
          expect {
            compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)
          }.to raise_error(/Failed to create gallery image definition/)
        end
      end
    end

    context 'when gallery image already exists' do
      let(:existing_image) do
        {
          tags: { 'stemcell_references' => 'other-stemcell', 'image_sha256' => 'abc123' },
          location: location
        }
      end

      before do
        allow(azure_client).to receive(:get_gallery_image_version)
          .with(gallery_name, image_definition, version)
          .and_return(existing_image)
        allow(azure_client).to receive(:create_update_gallery_image_version)
          .and_return(existing_image)
        allow(compute_gallery_manager).to receive(:flock).and_yield
      end

      it 'updates the existing gallery image tags' do
        compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

        expect(azure_client).to have_received(:create_update_gallery_image_version) do |_gallery_name, _image_def, _ver, params|
          expect(params['tags']['stemcell_references']).to include(stemcell_name)
          expect(params['tags']['stemcell_references']).to include('other-stemcell')
        end
      end

      it 'migrates old stemcell_name to stemcell_references' do
        existing_image[:tags] = { 'stemcell_name' => 'old-stemcell', 'image_sha256' => 'abc123' }

        compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

        expect(azure_client).to have_received(:create_update_gallery_image_version) do |_gallery_name, _image_def, _ver, params|
          expect(params['tags']['stemcell_references']).to include(stemcell_name)
          expect(params['tags']['stemcell_references']).to include('old-stemcell')
        end
      end
    end

    context 'when SHA256 mismatch occurs' do
      let(:existing_image) do
        {
          tags: { 'stemcell_references' => 'other-stemcell', 'image_sha256' => 'different-sha' },
          location: location
        }
      end

      before do
        allow(azure_client).to receive(:get_gallery_image_version)
          .with(gallery_name, image_definition, version)
          .and_return(existing_image)
      end

      it 'raises an error' do
        expect {
          compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)
        }.to raise_error(/SHA256 mismatch/)
      end
    end

    context 'when external image exists without BOSH CPI tags (created by different process)' do
      let(:external_image) do
        {
          tags: {}, # No BOSH CPI tags
          location: location
        }
      end

      before do
        allow(azure_client).to receive(:get_gallery_image_version)
          .with(gallery_name, image_definition, version)
          .and_return(external_image)
      end

      it 'raises an error when gallery image exists without BOSH CPI tags' do
        expect {
          compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)
        }.to raise_error(/already exists but was not created by BOSH CPI/)
      end
    end

    context 'when SHA256 validation scenarios' do
      let(:existing_image_with_sha) do
        {
          tags: { 'stemcell_references' => 'other-stemcell', 'image_sha256' => 'abc123' },
          location: location
        }
      end

      context 'when SHA256 checksums match' do
        before do
          allow(azure_client).to receive(:get_gallery_image_version)
            .with(gallery_name, image_definition, version)
            .and_return(existing_image_with_sha)
          allow(azure_client).to receive(:create_update_gallery_image_version)
            .and_return(existing_image_with_sha)
          allow(compute_gallery_manager).to receive(:flock).and_yield
        end

        it 'updates existing gallery image when SHA256 checksums match' do
          compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

          expect(azure_client).to have_received(:create_update_gallery_image_version) do |_gallery_name, _image_def, _ver, params|
            expect(params['tags']['stemcell_references']).to include(stemcell_name)
            expect(params['tags']['stemcell_references']).to include('other-stemcell')
            expect(params['tags']['image_sha256']).to eq('abc123')
          end
        end
      end

      context 'when existing image has no SHA256 checksum' do
        let(:existing_image_without_sha) do
          {
            tags: { 'stemcell_references' => 'other-stemcell' },
            location: location
          }
        end

        before do
          allow(azure_client).to receive(:get_gallery_image_version)
            .with(gallery_name, image_definition, version)
            .and_return(existing_image_without_sha)
          allow(azure_client).to receive(:create_update_gallery_image_version)
            .and_return(existing_image_without_sha)
          allow(compute_gallery_manager).to receive(:flock).and_yield
        end

        it 'adds SHA256 checksum to existing gallery image' do
          compute_gallery_manager.create_gallery_image(stemcell_name, image_definition, version, location, metadata)

          expect(azure_client).to have_received(:create_update_gallery_image_version) do |_gallery_name, _image_def, _ver, params|
            expect(params['tags']['image_sha256']).to eq('abc123')
          end
        end
      end
    end
  end

  describe '#delete_gallery_image' do
    let(:gallery_image) do
      {
        gallery_name: gallery_name,
        image_definition: image_definition,
        name: version,
        location: location,
        tags: { 'stemcell_references' => "#{stemcell_name},other-stemcell" }
      }
    end

    context 'when stemcell is in references and other references exist' do
      it 'removes the stemcell reference and updates the image' do
        expect(azure_client).to receive(:create_update_gallery_image_version)
          .with(gallery_name, image_definition, version, hash_including('tags'))

        result = compute_gallery_manager.delete_gallery_image(gallery_image, stemcell_name)
        expect(result).to be false # Image updated, not deleted
      end
    end

    context 'when stemcell is the only reference' do
      before do
        gallery_image[:tags] = { 'stemcell_references' => stemcell_name }
      end

      it 'deletes the entire gallery image' do
        expect(azure_client).to receive(:delete_gallery_image_version)
          .with(gallery_name, image_definition, version)

        result = compute_gallery_manager.delete_gallery_image(gallery_image, stemcell_name)
        expect(result).to be true # Image deleted
      end
    end

    context 'when using legacy stemcell_name tag' do
      before do
        gallery_image[:tags] = { 'stemcell_name' => stemcell_name }
      end

      it 'deletes the gallery image for backwards compatibility' do
        expect(azure_client).to receive(:delete_gallery_image_version)
          .with(gallery_name, image_definition, version)

        result = compute_gallery_manager.delete_gallery_image(gallery_image, stemcell_name)
        expect(result).to be true # Image deleted
      end
    end
  end

  describe '#ensure_gallery_image_in_target_location' do
    let(:gallery_image) do
      {
        gallery_name: gallery_name,
        image_definition: image_definition,
        name: version,
        location: location,
        target_regions: [location],
        replica_count: replica_count
      }
    end

    context 'when gallery image exists and is up to date' do
      before do
        allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
          .with(gallery_name, stemcell_name)
          .and_return(gallery_image)
      end

      it 'returns the existing gallery image' do
        result = compute_gallery_manager.ensure_gallery_image_in_target_location(stemcell_name, location)
        expect(result).to eq(gallery_image)
      end
    end

    context 'when gallery image needs replication to target location' do
      before do
        gallery_image[:target_regions] = ['westus']
        allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
          .with(gallery_name, stemcell_name)
          .and_return(gallery_image)
        allow(azure_client).to receive(:create_update_gallery_image_version)
          .and_return(gallery_image)
        allow(compute_gallery_manager).to receive(:flock).and_yield
      end

      it 'updates the gallery image with new target region' do
        compute_gallery_manager.ensure_gallery_image_in_target_location(stemcell_name, location)

        expect(azure_client).to have_received(:create_update_gallery_image_version) do |_gal_name, _img_def, _ver, params|
          expect(params['target_regions']).to include('westus', location)
        end
      end
    end

    context 'when gallery image does not exist' do
      before do
        allow(azure_client).to receive(:get_gallery_image_version_by_stemcell_name)
          .with(gallery_name, stemcell_name)
          .and_return(nil)
        allow(blob_manager).to receive(:get_blob_metadata)
          .and_return(nil)
      end

      it 'attempts to recover from blob metadata and returns nil if unsuccessful' do
        result = compute_gallery_manager.ensure_gallery_image_in_target_location(stemcell_name, location)
        expect(result).to be_nil
      end

      context 'when recovering from blob metadata with stringified disk_controller_types' do
        let(:blob_metadata) do
          {
            'image' => '{"publisher":"bosh","offer":"ubuntu-1804","sku":"gen2","version":"1.0.0"}',
            'compute_gallery_name' => gallery_name,
            'compute_gallery_image_definition' => image_definition,
            'disk_controller_types' => '["scsi","nvme"]',
            'generation' => 'gen2',
            'os_type' => 'linux',
            'architecture' => 'x86_64'
          }
        end

        before do
          allow(blob_manager).to receive(:get_blob_metadata)
            .with(default_storage_account_name, 'stemcell', "#{stemcell_name}.vhd")
            .and_return(blob_metadata)
          allow(azure_client).to receive(:get_gallery_image_version).and_return(nil)
          allow(azure_client).to receive(:get_gallery_image_definition).and_return(nil)
          allow(azure_client).to receive(:create_gallery_image_definition)
          allow(azure_client).to receive(:create_update_gallery_image_version).and_return(gallery_image)
          allow(blob_manager).to receive(:get_blob_uri).and_return('https://test.blob.uri')
          allow(compute_gallery_manager).to receive(:flock).and_yield
        end

        it 'parses disk_controller_types from JSON string to array' do
          compute_gallery_manager.ensure_gallery_image_in_target_location(stemcell_name, location)

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params['features']).to be_an(Array)
            expect(params['features']).to include(
              hash_including('name' => 'DiskControllerTypes', 'value' => 'SCSI,NVMe')
            )
          end
        end
      end
    end
  end

  describe '#create_stemcell_with_gallery' do
    let(:image_path) { '/fake/image/path.vhd' }
    let(:stemcell_properties) { { 'name' => 'ubuntu-1804', 'version' => '1.0', 'os_type' => 'linux', 'architecture' => 'x86_64' } }
    let(:location) { 'eastus' }
    let(:blob_creation_callback) { double('blob_creation_callback') }
    let(:fake_sha256) { 'fake-sha256-checksum' }

    before do
      allow(azure_config).to receive(:location).and_return(location)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new('fake-image-content'))
      allow_any_instance_of(Digest::SHA256).to receive(:hexdigest).and_return(fake_sha256)
      allow(blob_creation_callback).to receive(:call).and_return('bosh-stemcell-1234')
      allow(compute_gallery_manager).to receive(:create_gallery_image)
    end

    it 'processes stemcell creation workflow with gallery support' do
      result = compute_gallery_manager.create_stemcell_with_gallery(
        image_path, stemcell_properties, blob_creation_callback
      )

      expect(result).to eq('bosh-stemcell-1234')
      expect(blob_creation_callback).to have_received(:call).with(
        image_path,
        hash_including(
          'image_sha256' => fake_sha256,
          'compute_gallery_name' => gallery_name,
          'compute_gallery_image_definition' => 'ubuntu-1804'
        )
      )
      expect(compute_gallery_manager).to have_received(:create_gallery_image).with(
        'bosh-stemcell-1234', 'ubuntu-1804', '1.0.0', location, anything
      )
    end

    it 'validates location requirement' do
      allow(azure_config).to receive(:location).and_return(nil)

      expect {
        compute_gallery_manager.create_stemcell_with_gallery(
          image_path, stemcell_properties, blob_creation_callback
        )
      }.to raise_error(/Missing the property 'location'/)
    end

    it 'calculates SHA256 checksum' do
      allow(compute_gallery_manager).to receive(:calculate_image_sha256).and_call_original

      compute_gallery_manager.create_stemcell_with_gallery(
        image_path, stemcell_properties, blob_creation_callback
      )

      expect(compute_gallery_manager).to have_received(:calculate_image_sha256).with(image_path)
    end

    context 'when version has different formats' do
      {
        '1' => '1.0.0',
        '1.2' => '1.2.0',
        '1.2.3' => '1.2.3',
        '1.2.3.4' => '1.2.3'
      }.each do |input, expected|
        it "converts #{input} to semantic version #{expected}" do
          props = stemcell_properties.merge('version' => input)

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props, blob_creation_callback
          )

          expect(compute_gallery_manager).to have_received(:create_gallery_image).with(
            anything, anything, expected, anything, anything
          )
        end
      end
    end

    it 'validates invalid os_type' do
      invalid_props = stemcell_properties.merge('os_type' => 'invalid')

      allow(compute_gallery_manager).to receive(:create_gallery_image).and_call_original
      allow(azure_client).to receive(:get_gallery_image_version).and_return(nil)
      allow(azure_client).to receive(:get_gallery_image_definition).and_return(nil)

      expect {
        compute_gallery_manager.create_stemcell_with_gallery(
          image_path, invalid_props, blob_creation_callback
        )
      }.to raise_error(/Invalid os_type/)
    end

    it 'validates stemcell image file existence' do
      allow(File).to receive(:exist?).with(image_path).and_return(false)

      expect {
        compute_gallery_manager.create_stemcell_with_gallery(
          image_path, stemcell_properties, blob_creation_callback
        )
      }.to raise_error(/Image file does not exist/)
    end

    context 'hyperV-generation' do
      before do
        allow(compute_gallery_manager).to receive(:create_gallery_image).and_call_original
        allow(azure_client).to receive(:get_gallery_image_version).and_return(nil)
        allow(azure_client).to receive(:get_gallery_image_definition).and_return(nil)
        allow(azure_client).to receive(:create_gallery_image_definition)
        allow(azure_client).to receive(:create_update_gallery_image_version).and_return({})
        allow(blob_manager).to receive(:get_blob_uri).and_return('https://test.blob.uri')
      end

      it 'correctly formats gen2 parameter' do
        props_with_gen2 = stemcell_properties.merge('generation' => 'gen2')

        compute_gallery_manager.create_stemcell_with_gallery(
          image_path, props_with_gen2, blob_creation_callback
        )

        expect(azure_client).to have_received(:create_gallery_image_definition)
          .with(anything, anything, hash_including('hyperVGeneration' => 'V2'))
      end

      it 'uses default hyperV generation when not specified in stemcell properties' do
        compute_gallery_manager.create_stemcell_with_gallery(
          image_path, stemcell_properties, blob_creation_callback
        )

        expect(azure_client).to have_received(:create_gallery_image_definition)
          .with(anything, anything, hash_including('hyperVGeneration' => 'V1'))
      end

      context 'gen2 features' do
        it 'includes all gen2 features when present in metadata' do
          props_with_gen2_features = stemcell_properties.merge(
            'generation' => 'gen2',
            'disk_controller_types' => ['SCSI', 'NVMe'],
            'accelerated_networking' => true,
            'hibernation' => true,
            'security_type' => 'TrustedLaunchSupported'
          )

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_gen2_features, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params['features']).to be_an(Array)
            expect(params['features']).to include(
              hash_including('name' => 'DiskControllerTypes', 'value' => 'SCSI,NVMe')
            )
            expect(params['features']).to include(
              hash_including('name' => 'IsAcceleratedNetworkSupported', 'value' => 'True')
            )
            expect(params['features']).to include(
              hash_including('name' => 'IsHibernateSupported', 'value' => 'True')
            )
            expect(params['features']).to include(
              hash_including('name' => 'SecurityType', 'value' => 'TrustedLaunchSupported')
            )
          end
        end

        it 'includes SecurityType feature when security_type is present' do
          props_with_security = stemcell_properties.merge(
            'generation' => 'gen2',
            'security_type' => 'ConfidentialVMSupported'
          )

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_security, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params['features']).to be_an(Array)
            expect(params['features'].length).to eq(1)
            expect(params['features']).to include(
              hash_including('name' => 'SecurityType', 'value' => 'ConfidentialVMSupported')
            )
          end
        end

        it 'includes only present features in gen2 metadata' do
          props_partial_features = stemcell_properties.merge(
            'generation' => 'gen2',
            'accelerated_networking' => false
          )

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_partial_features, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params['features']).to be_an(Array)
            expect(params['features'].length).to eq(1)
            expect(params['features']).to include(
              hash_including('name' => 'IsAcceleratedNetworkSupported', 'value' => 'False')
            )
          end
        end

        it 'omits features parameter when no gen2 features are present' do
          props_gen2_no_features = stemcell_properties.merge('generation' => 'gen2')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_gen2_no_features, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params).not_to have_key('features')
          end
        end

        it 'omits features parameter for gen1 images even with feature fields' do
          props_gen1_with_features = stemcell_properties.merge(
            'generation' => 'gen1',
            'disk_controller_types' => ['SCSI'],
            'accelerated_networking' => true
          )

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_gen1_with_features, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params).not_to have_key('features')
          end
        end

        it 'normalizes disk controller types to proper case' do
          props_with_lowercase = stemcell_properties.merge(
            'generation' => 'gen2',
            'disk_controller_types' => ['scsi', 'nvme']
          )

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_lowercase, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params['features']).to include(
              hash_including('name' => 'DiskControllerTypes', 'value' => 'SCSI,NVMe')
            )
          end
        end

        it 'handles malformed JSON for disk_controller_types gracefully' do
          props_with_bad_json = stemcell_properties.merge(
            'generation' => 'gen2',
            'disk_controller_types' => '[invalid json'
          )

          allow(logger).to receive(:warn)

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_bad_json, blob_creation_callback
          )

          expect(logger).to have_received(:warn).with(/Ignoring invalid 'disk_controller_types' metadata/)
          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            if params['features']
              expect(params['features']).not_to include(
                hash_including('name' => 'DiskControllerTypes')
              )
            end
          end
        end
      end

      context 'architecture normalization' do
        it 'maps x86_64 to x64' do
          props_with_arch = stemcell_properties.merge('architecture' => 'x86_64')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_arch, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition)
            .with(anything, anything, hash_including('architecture' => 'x64'))
        end

        it 'normalizes arm64 to Arm64' do
          props_with_arch = stemcell_properties.merge('architecture' => 'arm64')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_arch, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition)
            .with(anything, anything, hash_including('architecture' => 'Arm64'))
        end

        it 'normalizes ARM64 (uppercase) to Arm64' do
          props_with_arch = stemcell_properties.merge('architecture' => 'ARM64')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_arch, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition)
            .with(anything, anything, hash_including('architecture' => 'Arm64'))
        end

        it 'passes through x64 unchanged' do
          props_with_arch = stemcell_properties.merge('architecture' => 'x64')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_arch, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition)
            .with(anything, anything, hash_including('architecture' => 'x64'))
        end

        it 'omits architecture parameter when not present in metadata' do
          props_without_arch = stemcell_properties.dup
          props_without_arch.delete('architecture')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_without_arch, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, _def, params|
            expect(params).not_to have_key('architecture')
          end
        end
      end

      context 'image definition naming with generation' do
        it 'appends generation suffix for gen2 stemcells' do
          props_with_gen2 = stemcell_properties.merge('generation' => 'gen2')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_gen2, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, image_def, _params|
            expect(image_def).to eq("#{stemcell_properties['name']}-gen2")
          end
        end

        it 'does not append suffix for gen1 stemcells' do
          props_with_gen1 = stemcell_properties.merge('generation' => 'gen1')

          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, props_with_gen1, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, image_def, _params|
            expect(image_def).to eq(stemcell_properties['name'])
          end
        end

        it 'does not append suffix when generation is not specified' do
          compute_gallery_manager.create_stemcell_with_gallery(
            image_path, stemcell_properties, blob_creation_callback
          )

          expect(azure_client).to have_received(:create_gallery_image_definition) do |_gallery, image_def, _params|
            expect(image_def).to eq(stemcell_properties['name'])
          end
        end
      end
    end
  end
end
