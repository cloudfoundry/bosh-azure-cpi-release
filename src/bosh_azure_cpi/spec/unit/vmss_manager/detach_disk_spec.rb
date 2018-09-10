# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#detach_disk' do
    context 'if everything ok' do
      it 'should not raise error' do
        expect(azure_client).to receive(:detach_disk_from_vmss_instance)
        expect do
          vmss_manager.detach_disk(instance_id_vmss, data_disk_obj)
        end.not_to raise_error
      end
    end
  end
end
