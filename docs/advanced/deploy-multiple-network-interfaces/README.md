# Deploy multiple network interfaces (NICs) for a VM in Azure Cloud Foundry

## Overview

A deployment job can be configured to have multiple IP addresses (multiple NICs) by being on multiple networks. This guidance describes how to assign multiple network interfaces to a instance (VM) in Cloud Foundry.

Here we take `multiple-vm-cf.yml` as an example, and assign 3 NICs to instance `cell_z1`.

## 1 Prerequisites

It is assumed that you have followed the [guidance](../../guidance.md) via ARM templates and have these resources ready:

* A deployment of BOSH.

* Manifests. By default, in these manifests, 1 instance has only 1 NIC assigned to it.

* Virtual network and subnets.

## 2 Create new subnets

Besides the existing subnets, create 2 more subnets (called `CloudFoundry2` and `CloudFoundry3`) for the new NICs. When a VM has multiple NICs, it is recommended that each NIC is in seperate subnet.

```
az network vnet subnet create --resource-group bosh-res-group --vnet-name boshvnet-crp --name CloudFoundry2 --address-prefix 10.0.40.0/24
az network vnet subnet create --resource-group bosh-res-group --vnet-name boshvnet-crp --name CloudFoundry3 --address-prefix 10.0.41.0/24
```
>**NOTE:** All NICs must be connected to Subnets within the same VNET, you cannot deploy a VM on multiple VNETs.

## 3 Update manifest

* Change `instance_type`

  On Azure, the VM size determines the number of NICS that you can create for a VM, please refer to this [document](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-sizes/) for the max NICs number allowd for different VM size.

  Here you need 3 NICs for instance `cell_z1`, so you can use `Standard_D3` which supports up to 4 NICs.

  You can create a new `resource_pool` (called `resource2_z1`), and set `instance_type` to `Standard_D3`. (if `instance_type` of the resource_pool already meets the requirement of VM size, you don't have to create new resource_pool) 

  ```yaml
  resource_pools:
  - name: resource_z1
    network: cf_private
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      instance_type: Standard_D1
      security_group: nsg-cf
  - name: resource2_z1
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      instance_type: Standard_D3
      security_group: nsg-cf
  ```

* Create new network specs (called `cf_private2` and `cf_private3`)

  ```yaml
  networks:
  - name: cf_private
    type: manual
    subnets:
    - range: 10.0.16.0/20
      gateway: 10.0.16.1
      dns: [168.63.129.16, 8.8.8.8]
      reserved: ["10.0.16.2 - 10.0.16.3"]
      static: ["10.0.16.4 - 10.0.16.100"]
      cloud_properties:
        virtual_network_name: boshvnet-crp
        subnet_name: CloudFoundry
  - name: cf_private2
    type: manual
    subnets:
    - range: 10.0.40.0/24
      gateway: 10.0.40.1
      dns: [168.63.129.16, 8.8.8.8]
      reserved: ["10.0.40.2 - 10.0.40.3"]
      static: ["10.0.40.4 - 10.0.40.100"]
      cloud_properties:
        virtual_network_name: boshvnet-crp
        subnet_name: CloudFoundry2
  - name: cf_private3
    type: dynamic
    subnets:
    - range: 10.0.41.0/24
      dns: [168.63.129.16, 8.8.8.8]
      cloud_properties:
        virtual_network_name: boshvnet-crp
        subnet_name: CloudFoundry3
  ```

* Assign additional networks and resource_pool to the instance

  ```yaml
  - name: cell_z1
    instances: 1
    templates:
    - name: consul_agent
      release: cf
    - name: rep
      release: diego
    - name: garden
      release: garden-linux
    - name: cflinuxfs2-rootfs-setup
      release: cflinuxfs2-rootfs
    - name: metron_agent
      release: cf
    resource_pool: resource2_z1
    networks:
      - name: cf_private
        default: [gateway, dns]
      - name: cf_private2
      - name: cf_private3
    update:
      serial: false
      max_in_flight: 1
    properties:
      metron_agent:
        zone: z1
      diego:
        rep:
          zone: z1
  ```
  >**NOTE:** when there are multiple NICs, BOSH requires explicit definition for default `dns` and `gateway` to decide which network's DNS settings to use and which network's gateway should be the default gateway on the VM. In this example, both `dns` and `gateway` are allocated to values in `cf_private`.

## 3 Deploy cloud foundry

  ```
  ./deploy_cloudfoundry.sh ~/example_manifests/multiple-vm-cf.yml
  ```

## 4 Verify

  Check network numbers by `ifconfig` in the VM

  ```
  bosh ssh cell_z1 0 ifconfig
  ```

  you will get outputs like this:

  ```
  cell_z1/
  eth0      Link encap:Ethernet  HWaddr 00:0d:3a:01:15:dc
            inet addr:10.0.16.107  Bcast:10.0.31.255  Mask:255.255.240.0
            inet6 addr: fe80::20d:3aff:fe01:15dc/64 Scope:Link
            UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
            RX packets:252819 errors:0 dropped:0 overruns:0 frame:0
            TX packets:61860 errors:0 dropped:0 overruns:0 carrier:0
            collisions:0 txqueuelen:1000
            RX bytes:357358429 (357.3 MB)  TX bytes:4537262 (4.5 MB)

  eth1      Link encap:Ethernet  HWaddr 00:0d:3a:01:12:2b
            inet addr:10.0.40.5  Bcast:10.0.40.255  Mask:255.255.255.0
            inet6 addr: fe80::20d:3aff:fe01:122b/64 Scope:Link
            UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
            RX packets:2 errors:0 dropped:0 overruns:0 frame:0
            TX packets:30 errors:0 dropped:0 overruns:0 carrier:0
            collisions:0 txqueuelen:1000
            RX bytes:762 (762.0 B)  TX bytes:2172 (2.1 KB)

  eth2      Link encap:Ethernet  HWaddr 00:0d:3a:01:15:69
            inet addr:10.0.41.4  Bcast:10.0.41.255  Mask:255.255.255.0
            inet6 addr: fe80::20d:3aff:fe01:1569/64 Scope:Link
            UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
            RX packets:2 errors:0 dropped:0 overruns:0 frame:0
            TX packets:30 errors:0 dropped:0 overruns:0 carrier:0
            collisions:0 txqueuelen:1000
            RX bytes:762 (762.0 B)  TX bytes:2172 (2.1 KB)

  lo        Link encap:Local Loopback
            inet addr:127.0.0.1  Mask:255.0.0.0
            inet6 addr: ::1/128 Scope:Host
            UP LOOPBACK RUNNING  MTU:65536  Metric:1
            RX packets:2010 errors:0 dropped:0 overruns:0 frame:0
            TX packets:2010 errors:0 dropped:0 overruns:0 carrier:0
            collisions:0 txqueuelen:0
            RX bytes:265696 (265.6 KB)  TX bytes:265696 (265.6 KB)

  ```
