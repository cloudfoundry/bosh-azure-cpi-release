# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  describe '#create' do
    let(:agent_util) { instance_double(Bosh::AzureCloud::BoshAgentUtil) }
    let(:network_spec) { {} }
    let(:config) { instance_double(Bosh::AzureCloud::Config) }

    let(:props_factory) do
      Bosh::AzureCloud::PropsFactory.new(
        Bosh::AzureCloud::ConfigFactory.build(
          mock_cloud_properties_merge('azure' => { 'use_managed_disks' => true })
        )
      )
    end

    let(:vm_props_with_security_profile) do
      props_factory.parse_vm_props(
        'instance_type' => 'Standard_D1',
        'security_profile' => {
          'security_type' => 'TrustedLaunch',
          'secure_boot_enabled' => false
        }
      )
    end

    before do
      allow(vm_manager2).to receive(:_get_stemcell_info).and_return(stemcell_info)
      allow(azure_client).to receive(:create_virtual_machine)
    end

    def create_vm(vm_props)
      vm_manager2.create(bosh_vm_meta, location, vm_props, disk_cids, network_configurator, env, agent_util, network_spec, config)
    end

    describe '#security_profile' do
      context 'when no security profile is configured' do
        let(:vm_props) { props_factory.parse_vm_props('instance_type' => 'Standard_D1') }

        it 'does not send a security profile at all' do
          _, vm_params = create_vm(vm_props)
          expect(vm_params).not_to have_key(:security_profile)
        end
      end

      context 'when a security profile is configured in the vm_type' do
        it 'passes the resolved settings to the VM params, with vTPM forced on' do
          _, vm_params = create_vm(vm_props_with_security_profile)

          expect(vm_params[:security_profile]).to eq(
            security_type: 'TrustedLaunch',
            uefi_settings: { secure_boot_enabled: false, vtpm_enabled: true }
          )
        end
      end

      context 'when the security type is Standard' do
        let(:vm_props) do
          props_factory.parse_vm_props(
            'instance_type' => 'Standard_D1',
            'security_profile' => {
              'security_type' => 'Standard',
              'secure_boot_enabled' => false
            }
          )
        end

        it 'sends the security type with no UEFI settings' do
          _, vm_params = create_vm(vm_props)

          expect(vm_params[:security_profile]).to eq(
            security_type: 'Standard',
            uefi_settings: nil
          )
        end
      end
    end
  end
end
