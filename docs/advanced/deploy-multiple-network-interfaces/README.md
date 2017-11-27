# Deploy multiple network interfaces (NICs) for a VM in Azure Cloud Foundry

## Overview

A deployment job can be configured to have multiple IP addresses (multiple NICs) by being on multiple networks. This guidance describes how to assign multiple network interfaces to a instance (VM) in Cloud Foundry.

As an example, you can assign 3 NICs to instance_group `cell`.

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

1. Update cloud config

    1. Update `vm_types`

        On Azure, the VM size determines the number of NICS that you can create for a VM, please refer to this [document](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-sizes/) for the max NICs number allowd for different VM size.

        Here you need 3 NICs for instance `cell_z1`, so you can use `Standard_D3` which supports up to 4 NICs.

        You can create a new `vm_type` (called `standard_d3`), and set `instance_type` to `Standard_D3`.

        ```yaml
        vm_types:
        - name: standard_d3
          cloud_properties:
            instance_type: Standard_D3
            ephemeral_disk:
              size: 10240
        ```
    
    1. Update network specs.
    
        ```yaml
        networks:
        - name: default
          type: manual
          subnets:
          - range: ((internal_cidr))
            gateway: ((internal_gw))
            azs: [z1, z2, z3]
            dns: [8.8.8.8, 168.63.129.16]
            reserved: [((internal_gw))/30]
            cloud_properties:
              virtual_network_name: ((vnet_name))
              subnet_name: ((subnet_name))
              security_group: ((security_group))
        - name: network2
          type: manual
          subnets:
          - range: ((internal_cidr_2))
            gateway: ((internal_gw_2))
            azs: [z1, z2, z3]
            dns: [8.8.8.8, 168.63.129.16]
            reserved: [((internal_gw_2))/30]
            cloud_properties:
              virtual_network_name: ((vnet_name))
              subnet_name: ((subnet_name_2))
              security_group: ((security_group))
        - name: network3
          type: manual
          subnets:
          - range: ((internal_cidr_3))
            gateway: ((internal_gw_3))
            azs: [z1, z2, z3]
            dns: [8.8.8.8, 168.63.129.16]
            reserved: [((internal_gw_3))/30]
            cloud_properties:
              virtual_network_name: ((vnet_name))
              subnet_name: ((subnet_name_3))
              security_group: ((security_group))
        ```

    1. Add the following lines into the `bosh update-cloud-config` command in `deploy_cloud_foundry.sh`.

        ```
        -v internal_cidr_2=10.0.40.0/24 \
        -v internal_gw_2=10.0.40.1 \
        -v subnet_name_2=CloudFoundry2 \
        -v internal_cidr_3=10.0.41.0/24 \
        -v internal_gw_3=10.0.41.1 \
        -v subnet_name_3=CloudFoundry3 \
        ```

1. Assign additional networks and vm_type to the instance

    1. Download the ops file [`use-multiple-nics.yml`](./use-multiple-nics.yml) to `~/use-multiple-nics.yml`.

    1. Add the line `-o ~/use-multiple-nics.yml` to the `bosh -n -d cf deploy` command in `deploy_cloud_foundry.sh`.

        >**NOTE:** When there are multiple NICs, BOSH requires explicit definition for default `dns` and `gateway` to decide which network's DNS settings to use and which network's gateway should be the default gateway on the VM. In this example, both `dns` and `gateway` are allocated to values in `default` network.

## 3 Deploy cloud foundry

```
./deploy_cloud_foundry.sh
```

## 4 Verify

Check network numbers by `ifconfig` in the VM

```
bosh -e azure -d cf ssh diego-cell/0 ifconfig
```

you will get outputs like this:

```
Using environment '10.0.0.4' as client 'admin'

Using deployment 'cf'

Task 80. Done
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stderr | Unauthorized use is strictly prohibited. All access and activity
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stderr | is subject to logging and monitoring.
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout | eth0      Link encap:Ethernet  HWaddr 00:0d:3a:40:a9:3b
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           inet addr:10.0.16.16  Bcast:10.0.31.255  Mask:255.255.240.0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX packets:317660 errors:0 dropped:0 overruns:0 frame:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           TX packets:135706 errors:0 dropped:0 overruns:0 carrier:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           collisions:0 txqueuelen:1000
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX bytes:435253140 (435.2 MB)  TX bytes:12975351 (12.9 MB)
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout | eth1      Link encap:Ethernet  HWaddr 00:0d:3a:40:ab:d9
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           inet addr:10.0.40.4  Bcast:10.0.40.255  Mask:255.255.255.0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX packets:2 errors:0 dropped:0 overruns:0 frame:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           TX packets:22 errors:0 dropped:0 overruns:0 carrier:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           collisions:0 txqueuelen:1000
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX bytes:762 (762.0 B)  TX bytes:1524 (1.5 KB)
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout | eth2      Link encap:Ethernet  HWaddr 00:0d:3a:40:aa:58
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           inet addr:10.0.41.4  Bcast:10.0.41.255  Mask:255.255.255.0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX packets:2 errors:0 dropped:0 overruns:0 frame:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           TX packets:22 errors:0 dropped:0 overruns:0 carrier:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           collisions:0 txqueuelen:1000
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX bytes:762 (762.0 B)  TX bytes:1524 (1.5 KB)
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout | lo        Link encap:Local Loopback
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           inet addr:127.0.0.1  Mask:255.0.0.0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           UP LOOPBACK RUNNING  MTU:65536  Metric:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX packets:22050 errors:0 dropped:0 overruns:0 frame:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           TX packets:22050 errors:0 dropped:0 overruns:0 carrier:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           collisions:0 txqueuelen:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX bytes:2839828 (2.8 MB)  TX bytes:2839828 (2.8 MB)
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout | silk-vtep Link encap:Ethernet  HWaddr ee:ee:0a:ff:24:00
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           inet addr:10.255.36.0  Bcast:0.0.0.0  Mask:255.255.0.0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           UP BROADCAST RUNNING MULTICAST  MTU:1450  Metric:1
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX packets:0 errors:0 dropped:0 overruns:0 frame:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           collisions:0 txqueuelen:0
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |           RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stdout |
diego-cell/54992d97-4056-4cb9-9278-7d7c5095bc95: stderr | Connection to 10.0.16.16 closed.

Succeeded
```
