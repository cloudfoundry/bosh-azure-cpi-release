# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMSSManager do
  include_context 'shared stuff for vm managers'
  describe '#attach_disk' do
    context 'if everything ok' do
      it 'should not raise error' do
        allow(azure_client).to receive(:get_managed_disk_by_name)
          .and_return(id: 'fake_id')
        expect(azure_client).to receive(:attach_disk_to_vmss_instance)
        expect do
          vmss_manager.attach_disk(instance_id_vmss, data_disk_obj)
        end.not_to raise_error
      end
    end
  end
end
