# frozen_string_literal: true

require 'spec_helper'
require 'unit/vms/shared_stuff.rb'

describe Bosh::AzureCloud::VMManagerAdaptive do
  include_context 'shared stuff for vm managers'
  context 'when vmss enabled' do
    let(:vm_manager) { instance_double(Bosh::AzureCloud::VMManager) }
    let(:vmss_manager) { instance_double(Bosh::AzureCloud::VMSSManager) }
    it 'should not raise error' do
      expect(dynamic_network).to receive(:is_a?).with(Bosh::AzureCloud::ManualNetwork) { false }
      allow(Bosh::AzureCloud::VMManager).to receive(:new).and_return(vm_manager)
      allow(Bosh::AzureCloud::VMSSManager).to receive(:new).and_return(vmss_manager)
      allow(network_configurator).to receive(:networks)
        .and_return([dynamic_network])
      expect(vmss_manager).to receive(:create)
      expect do
        vm_manager_adaptive.create(bosh_vm_meta, vm_props, network_configurator, env_with_group)
      end.not_to raise_error
    end

    it 'should call vmss manager' do
      allow(Bosh::AzureCloud::VMManager).to receive(:new).and_return(vm_manager)
      allow(Bosh::AzureCloud::VMSSManager).to receive(:new).and_return(vmss_manager)
      expect(vmss_manager).to receive(:find).with(instance_id_vmss)
      expect(vmss_manager).to receive(:delete).with(instance_id_vmss)
      expect(vmss_manager).to receive(:reboot).with(instance_id_vmss)
      expect(vmss_manager).to receive(:set_metadata).with(instance_id_vmss, meta_data)
      expect(vmss_manager).to receive(:attach_disk).with(instance_id_vmss, data_disk_id)
      expect(vmss_manager).to receive(:detach_disk).with(instance_id_vmss, data_disk_id)
      expect do
        vm_manager_adaptive.find(instance_id_vmss)

        vm_manager_adaptive.delete(instance_id_vmss)

        vm_manager_adaptive.reboot(instance_id_vmss)

        vm_manager_adaptive.set_metadata(instance_id_vmss, meta_data)

        vm_manager_adaptive.attach_disk(instance_id_vmss, data_disk_id)

        vm_manager_adaptive.detach_disk(instance_id_vmss, data_disk_id)
      end.not_to raise_error
    end
  end

  context 'when vmss disabled' do
    let(:vm_manager) { instance_double(Bosh::AzureCloud::VMManager) }
    let(:vmss_manager) { instance_double(Bosh::AzureCloud::VMSSManager) }
    it 'should not raise error' do
      allow(Bosh::AzureCloud::VMManager).to receive(:new).and_return(vm_manager)
      allow(Bosh::AzureCloud::VMSSManager).to receive(:new).and_return(vmss_manager)
      expect(vm_manager).to receive(:create)
      vm_manager_adaptive_vmss_disabled.create(bosh_vm_meta, vm_props, network_configurator, env_with_group)
    end
  end
end
