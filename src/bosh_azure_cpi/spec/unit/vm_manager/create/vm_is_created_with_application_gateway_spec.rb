require 'spec_helper'
require "unit/vm_manager/create/shared_stuff.rb"

describe Bosh::AzureCloud::VMManager do
  include_context "shared stuff for vm manager"

  describe "#create" do
    context "when VM is created" do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Application Gateway
      context "#application_gateway" do
        let(:application_gateway_name) { 'fake-ag-name' }
        let(:resource_pool) {
          {
            'instance_type'       => 'Standard_D1',
            'application_gateway' => application_gateway_name
          }
        }
        let(:public_ip) { { :ip_address => 'public-ip' } }
        let(:tags0) {
          {
            'user-agent' => 'bosh',
            'application_gateway' => application_gateway_name
          }
        }
        let(:tags1) {
          {
            'user-agent' => 'bosh'
          }
        }
        context "with the application gateway provided in resource_pool" do           
          let(:network_interface0) {
            {
              :name => "#{instance_id}-0",
              :tags=> tags0,
              :private_ip => "fake-private-ip0"
            }
          }
          let(:network_interface1) {
            {
              :name => "#{instance_id}-1",
              :tags=> tags1,
              :private_ip => "fake-private-ip1"
            }
          }
          let(:lock_application_gateway) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }

          before do
            allow(client2).to receive(:get_network_interface_by_name).
              and_return(network_interface0, network_interface1)
            allow(client2).to receive(:create_availability_set)
          end

          context "when the lock of application gateway is not acquired" do
            before do
              allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_application_gateway)
              allow(lock_application_gateway).to receive(:lock).and_return(false, true)
              allow(lock_application_gateway).to receive(:expired).and_return("fake-expired-value")
              allow(lock_application_gateway).to receive(:unlock)
            end

            context "when updating application gateway timeouts" do
              before do
                allow(lock_application_gateway).to receive(:wait).and_raise("timeout")
              end

              it "should raise a timeout error" do
                expect(client2).not_to receive(:add_backend_address_of_application_gateway)
                expect(client2).to receive(:delete_network_interface).exactly(2).times
                expect(client2).to receive(:delete_backend_address_of_application_gateway).exactly(1).times

                expect {
                  vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.to raise_error { |error|
                  expect(error.inspect).to match(/#<Bosh::Clouds::VMCreationFailed: #<RuntimeError: timeout>/)
                }
              end
            end

            context "when updating application gateway finishes before it timeouts" do
              before do
                allow(lock_application_gateway).to receive(:wait)
                allow(lock_application_gateway).to receive(:unlock)
              end

              context "and the association succeeded" do
                it "should succeed" do
                  expect(client2).not_to receive(:delete_virtual_machine)
                  expect(client2).not_to receive(:delete_network_interface)

                  expect(client2).to receive(:create_network_interface).twice
                  expect(client2).to receive(:add_backend_address_of_application_gateway).
                    with(application_gateway_name, network_interface0[:private_ip])
                  expect{
                    vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  }.not_to raise_error
                end
              end

              context "and the association failed" do
                before do
                  allow(client2).to receive(:create_network_interface)
                  allow(client2).to receive(:add_backend_address_of_application_gateway).
                    and_raise("association failed")
                end

                it "should delete nics, disassociate the ip from AG, and then raise an error" do
                  expect(client2).to receive(:delete_network_interface).exactly(2).times
                  expect(client2).to receive(:delete_backend_address_of_application_gateway).exactly(1).times
                  
                  expect{
                    vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                  }.to raise_error /association failed/
                end
              end
            end
          end

          context "when the lock of application gateway is acquired" do
            before do
              allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_application_gateway)
              allow(lock_application_gateway).to receive(:lock).and_return(true)
              allow(lock_application_gateway).to receive(:unlock)
            end

            context "and the association succeeded" do
              it "should succeed" do
                expect(client2).not_to receive(:delete_virtual_machine)
                expect(client2).not_to receive(:delete_network_interface)

                expect(client2).to receive(:create_network_interface).twice
                expect(client2).to receive(:add_backend_address_of_application_gateway).
                  with(application_gateway_name, network_interface0[:private_ip])
                expect{
                  vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.not_to raise_error
              end
            end

            context "and the association failed" do
              before do
                allow(client2).to receive(:create_network_interface)
                allow(client2).to receive(:add_backend_address_of_application_gateway).
                  and_raise("association failed")
              end

              it "should delete nics, disassociate the ip from AG, and then raise an error" do
                expect(client2).to receive(:delete_network_interface).exactly(2).times
                expect(client2).to receive(:delete_backend_address_of_application_gateway).exactly(1).times

                expect{
                  vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
                }.to raise_error /association failed/
              end
            end
          end
        end
        
        context "with the application gateway provided in resource_pool but the ip address of network interface is not static" do
          let(:network_interface0) {
            {
              :name => "#{instance_id}-0",
              :tags=> tags0,
              :private_ip => nil
            }
          }
          let(:network_interface1) {
            {
              :name => "#{instance_id}-1",
              :tags=> tags1,
              :private_ip => "fake-private-ip1"
            }
          }
          
          before do
            allow(client2).to receive(:get_network_interface_by_name).
              and_return(network_interface0, network_interface1)
            allow(client2).to receive(:create_availability_set)
          end

          it "should raise an error" do
            expect(client2).not_to receive(:add_backend_address_of_application_gateway)

            expect(client2).to receive(:create_network_interface).twice
            expect(client2).to receive(:delete_network_interface).twice
            expect{
              vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
            }.to raise_error /You need to use static IP for the VM which will be bound to the application gateway/
          end
        end
      end
    end
  end
end