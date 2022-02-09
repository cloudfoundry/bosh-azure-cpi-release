# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - default_security_group
  describe '#root_disk_type' do
    context 'when only instance_type is specified' do
      context 'when instance_type does not support SSD disks' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'Standard_F1'
          )
        end

        it 'should return root disk type: Standard_LRS' do
          expect(
            vm_manager2.send(:_get_root_disk_type, vm_props)
          ).to be('Standard_LRS')
        end
      end

      context 'when instance_type supports SSD disks' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'Standard_B1s'
          )
        end

        it 'should return root disk type: Premium_LRS' do
          expect(
            vm_manager2.send(:_get_root_disk_type, vm_props)
          ).to be('Premium_LRS')
        end
      end
    end

    context 'when instance_type and storage_account_type are specified' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'Standard_F1',
          'storage_account_type' => 'Premium_LRS'
        )
      end

      it 'should return root disk type: Premium_LRS' do
        expect(
          vm_manager2.send(:_get_root_disk_type, vm_props)
        ).to be('Premium_LRS')
      end
    end

    context 'when instance_type and root_disk.type are specified' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'Standard_F1',
          'root_disk' => {
            'type' => 'Premium_LRS'
          }
        )
      end

      it 'should return root disk type: Premium_LRS' do
        expect(
          vm_manager2.send(:_get_root_disk_type, vm_props)
        ).to be('Premium_LRS')
      end
    end

    context 'when instance_type, storage_account_type and root_disk.type are specified' do
      let(:vm_props) do
        props_factory.parse_vm_props(
          'instance_type' => 'Standard_F1',
          'storage_account_type' => 'Standard_LRS',
          'root_disk' => {
            'type' => 'Premium_LRS'
          }
        )
      end

      it 'should return root disk type: Premium_LRS' do
        expect(
          vm_manager2.send(:_get_root_disk_type, vm_props)
        ).to be('Premium_LRS')
      end
    end
  end
end
