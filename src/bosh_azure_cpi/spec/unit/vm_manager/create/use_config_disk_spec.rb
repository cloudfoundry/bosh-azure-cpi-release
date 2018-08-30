# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

# RSpec::Matchers.define :need_mock_command do
#   match { |actual| { actual.include?('mount') || actual.include?('mkfs.ext4') } }
# end
describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    let(:command_runner) { Bosh::AzureCloud::CommandRunner.new }
    before do
      allow(stemcell_info).to receive(:os_type).and_return('linux')
      allow(vm_manager_config_disk).to receive(:_get_stemcell_info).and_return(stemcell_info)
      allow(storage_account_manager).to receive(:default_storage_account_name)
        .and_return(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
      allow(Etc).to receive(:getpwuid)
        .and_return(OpenStruct.new(name: 'vcap'))
    end
    context 'when use config disk' do
      context 'when everything ok' do
        it 'should prepare config disk' do
          expect(azure_client).to receive(:create_virtual_machine)
          expect(command_runner).to receive(:run_command).with(/sudo -n mount/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/mkfs/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/sudo -n chown/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/sudo -n umount/).exactly(1).times
          expect(command_runner).to receive(:run_command).exactly(2).times.and_call_original

          expect(Bosh::AzureCloud::CommandRunner).to receive(:new).and_return(command_runner)

          expect(blob_manager).to receive(:create_vhd_page_blob)
          expect(blob_manager).to receive(:delete_blob)
          expect(blob_manager).to receive(:get_blob_uri)
          expect(disk_manager2).to receive(:create_disk_from_blob)
          expect(disk_manager2).to receive(:get_data_disk)
          expect do
            vm_manager_config_disk.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
          end.not_to raise_error
        end
      end
      context 'when mkfs failed' do
        it 'should raise an error and clean up' do
          expect(Bosh::AzureCloud::CommandRunner).to receive(:new).and_return(command_runner)
          expect(command_runner).to receive(:run_command).with(/mkfs/).and_raise('failed to mkfs')
          expect(command_runner).to receive(:run_command).with(/sudo -n umount/).exactly(1).times
          expect(command_runner).to receive(:run_command).exactly(1).times.and_call_original

          expect(blob_manager).not_to receive(:create_vhd_page_blob)
          expect(blob_manager).not_to receive(:delete_blob)
          expect(blob_manager).not_to receive(:get_blob_uri)
          expect(disk_manager2).not_to receive(:create_disk_from_blob)
          expect(azure_client).to receive(:delete_network_interface).exactly(2).times
          expect do
            vm_manager_config_disk.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
          end.to raise_error Bosh::Clouds::CloudError, /Failed to prepare the config disk/
        end
      end

      context 'when create disk failed' do
        it 'should raise an error and clean up' do
          expect(command_runner).to receive(:run_command).with(/sudo -n mount/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/mkfs/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/sudo -n chown/).exactly(1).times
          expect(command_runner).to receive(:run_command).with(/sudo -n umount/).exactly(1).times
          expect(command_runner).to receive(:run_command).exactly(2).times.and_call_original

          expect(Bosh::AzureCloud::CommandRunner).to receive(:new).and_return(command_runner)

          expect(blob_manager).to receive(:create_vhd_page_blob)
          expect(blob_manager).to receive(:delete_blob)
          expect(blob_manager).to receive(:get_blob_uri)
          expect(disk_manager2).to receive(:create_disk_from_blob).and_raise('create disk failed')
          expect(azure_client).to receive(:delete_network_interface).exactly(2).times
          expect do
            vm_manager_config_disk.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env)
          end.to raise_error Bosh::Clouds::CloudError, /Failed to prepare the config disk/
        end
      end
    end
  end
end
