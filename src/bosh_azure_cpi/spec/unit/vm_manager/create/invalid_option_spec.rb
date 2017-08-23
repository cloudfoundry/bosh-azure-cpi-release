require 'spec_helper'
require "unit/vm_manager/create/shared_stuff.rb"

describe Bosh::AzureCloud::VMManager do
  include_context "shared stuff for vm manager"

  describe "#create" do
    context "when instance_type is not provided" do
      let(:resource_pool) { {} }

      it "should raise an error" do
        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).to receive(:list_network_interfaces_by_keyword).with(resource_group_name, vm_name).and_return([])
        expect(client2).to receive(:get_public_ip_by_name).
          with(resource_group_name, vm_name).
          and_return({ :ip_address => "public-ip" })
        expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)

        expect {
          vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
        }.to raise_error /missing required cloud property `instance_type'/
      end
    end

    context "when an error is thrown during cleanup" do
      let(:resource_pool) { {} } # missing required cloud property `instance_type' causes a cleanup

      before do
        allow(client2).to receive(:get_public_ip_by_name).
          with(resource_group_name, vm_name).
          and_return({ :ip_address => "public-ip" })
        allow(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name).and_raise("Error during cleanup")
      end

      it "should raise an error" do
        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)
        expect(client2).to receive(:list_network_interfaces_by_keyword).with(resource_group_name, vm_name).and_return([])

        expect {
          vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
        }.to raise_error /Error during cleanup/
      end
    end

    context "when the resource group name is not specified in the network spec" do
      context "when subnet is not found in the default resource group" do
        before do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:get_load_balancer_by_name).
            with(resource_pool['load_balancer'])
            .and_return(load_balancer)
          allow(client2).to receive(:list_public_ips).
            and_return([{
              :ip_address => "public-ip"
            }])
          allow(client2).to receive(:get_network_subnet_by_name).
            with(MOCK_RESOURCE_GROUP_NAME, "fake-virtual-network-name", "fake-subnet-name").
            and_return(nil)
        end

        it "should raise an error" do
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the subnet `fake-virtual-network-name\/fake-subnet-name' in the resource group `#{MOCK_RESOURCE_GROUP_NAME}'/
        end
      end

      context "when network security group is not found in the default resource group" do
        before do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:get_load_balancer_by_name).
            with(resource_pool['load_balancer'])
            .and_return(load_balancer)
          allow(client2).to receive(:list_public_ips).
            and_return([{
              :ip_address => "public-ip"
            }])
          allow(client2).to receive(:get_network_security_group_by_name).
            with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
            and_return(nil)
        end

        it "should raise an error" do
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the network security group `fake-default-nsg-name'/
        end
      end
    end

    context "when the resource group name is specified in the network spec" do
      before do
        allow(client2).to receive(:get_network_security_group_by_name).
          with("fake-resource-group-name", MOCK_DEFAULT_SECURITY_GROUP).
          and_return(security_group)
        allow(manual_network).to receive(:resource_group_name).
          and_return("fake-resource-group-name")
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer'])
          .and_return(load_balancer)
        allow(client2).to receive(:list_public_ips).
          and_return([{
            :ip_address => "public-ip"
          }])
      end

      context "when subnet is not found in the specified resource group" do
        it "should raise an error" do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:get_network_subnet_by_name).
            with("fake-resource-group-name", "fake-virtual-network-name", "fake-subnet-name").
            and_return(nil)
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the subnet `fake-virtual-network-name\/fake-subnet-name' in the resource group `fake-resource-group-name'/
        end
      end

      context "when network security group is not found in the specified resource group nor the default resource group" do
        before do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:get_network_security_group_by_name).
            with(MOCK_RESOURCE_GROUP_NAME, MOCK_DEFAULT_SECURITY_GROUP).
            and_return(nil)
          allow(client2).to receive(:get_network_security_group_by_name).
            with("fake-resource-group-name", MOCK_DEFAULT_SECURITY_GROUP).
            and_return(nil)
        end

        it "should raise an error" do
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the network security group `fake-default-nsg-name'/
        end
      end
    end

    context "when public ip is not found" do
      before do
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer'])
          .and_return(load_balancer)
      end

      context "when the public ip list azure returns is empty" do
        it "should raise an error" do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:list_public_ips).
            and_return([])

          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_network_interface)
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the public IP address/
        end
      end

      context "when the public ip list azure returns does not match the configured one" do
        let(:public_ips) {
          [
            {
              :ip_address => "public-ip"
            },
            {
              :ip_address => "not-public-ip"
            }
          ]
        }

        it "should raise an error" do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
          allow(client2).to receive(:list_public_ips).
            and_return(public_ips)
          allow(vip_network).to receive(:public_ip).
            and_return("not-exist-public-ip")

          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_network_interface)
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /Cannot find the public IP address/
        end
      end
    end

    context "when load balancer can not be found" do
      before do
        allow(client2).to receive(:list_network_interfaces_by_keyword).
          with(resource_group_name, vm_name).
          and_return([])
      end

      it "should raise an error" do
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer']).
          and_return(nil)

        expect(client2).not_to receive(:delete_virtual_machine)
        expect(client2).not_to receive(:delete_network_interface)

        expect {
          vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
        }.to raise_error /Cannot find the load balancer/
      end
    end

    context "when network interface is not created" do
      before do
        allow(client2).to receive(:get_network_subnet_by_name).
          and_return(subnet)
        allow(client2).to receive(:get_load_balancer_by_name).
          with(resource_pool['load_balancer']).
          and_return(load_balancer)
        allow(client2).to receive(:list_public_ips).
          and_return([{
            :ip_address => "public-ip"
          }])
        allow(client2).to receive(:create_network_interface).
          and_raise("network interface is not created")
      end

      context "when none of network interface is created" do
        before do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
        end

        it "should raise an error and do not delete any network interface" do
          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_network_interface)
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /network interface is not created/
        end
      end

      context "when one network interface is created and the another one is not" do
        let(:network_interface) {
          {
            :id   => "/subscriptions/fake-subscription/resourceGroups/fake-resource-group/providers/Microsoft.Network/networkInterfaces/#{vm_name}-x",
            :name => "#{vm_name}-x"
          }
        }

        before do
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([network_interface])
          allow(client2).to receive(:get_network_subnet_by_name).
            and_return(subnet)
          allow(client2).to receive(:get_load_balancer_by_name).
            with(resource_pool['load_balancer']).
            and_return(load_balancer)
          allow(client2).to receive(:list_public_ips).
            and_return([{
              :ip_address => "public-ip"
            }])
        end

        it "should delete the (possible) existing network interface and raise an error" do
          expect(client2).to receive(:delete_network_interface).once
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /network interface is not created/
        end
      end

      context "when dynamic public IP is created" do
        let(:dynamic_public_ip) { 'fake-dynamic-public-ip' }

        before do
          resource_pool['assign_dynamic_public_ip'] = true
          allow(client2).to receive(:get_public_ip_by_name).
            with(resource_group_name, vm_name).and_return(dynamic_public_ip)
          allow(client2).to receive(:list_network_interfaces_by_keyword).
            with(resource_group_name, vm_name).
            and_return([])
        end

        it "should delete the dynamic public IP" do
          expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)
          expect {
            vm_manager.create(instance_id, location, stemcell_info, resource_pool, network_configurator, env)
          }.to raise_error /network interface is not created/
        end
      end
    end
  end
end
