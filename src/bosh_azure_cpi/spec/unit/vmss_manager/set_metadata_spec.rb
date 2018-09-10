# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#set_metadata' do
    context 'when everything ok' do
      it 'should not raise error' do
        allow(azure_client).to receive(:set_vmss_instance_metadata)
        expect do
          vmss_manager.set_metadata(instance_id_vmss, meta_data)
        end.not_to raise_error
      end
    end
  end
end
