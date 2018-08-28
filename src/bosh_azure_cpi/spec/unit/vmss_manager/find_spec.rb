# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#find' do
    context 'when everything ok' do
      it 'should not raise error' do
        allow(azure_client).to receive(:get_vmss_instance)
        expect do
          vmss_manager.find(instance_id_vmss)
        end.not_to raise_error
      end
    end
  end
end
