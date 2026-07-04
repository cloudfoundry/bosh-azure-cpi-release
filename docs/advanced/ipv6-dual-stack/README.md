# IPv6 Dual-Stack Deployments on Azure

## Overview

The Azure CPI supports **dual-stack (IPv4 + IPv6)** networking, allowing VMs to receive both an IPv4 and an IPv6 address on the same NIC. This is useful for workloads that need to serve or consume IPv6 traffic while maintaining IPv4 connectivity.

> **Azure limitation:** IPv6-only VMs are not supported. Every NIC must include at least one IPv4 `ipConfiguration`. There is no single-stack IPv6 mode on Azure. See [IPv6 overview — Limitations](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/ipv6-overview#limitations).

## How It Works

### Azure Side

A dual-stack Azure subnet carries both an IPv4 CIDR and an IPv6 CIDR, exposed through the `addressPrefixes` (array) property on the subnet resource. When the CPI creates a NIC for a dual-stack VM, it builds **two `ipConfigurations`** on a single NIC:

| ipConfiguration | IP version | Primary | Notes |
|-----------------|------------|---------|-------|
| `ipconfig-v4`   | IPv4       | Yes     | Carries public IP, load balancer pools, application gateway pools |
| `ipconfig-v6`   | IPv6       | No      | Carries IPv6-specific load balancer pools (if configured) |

### BOSH Side

The BOSH director uses the `nic_group` property to express that two network definitions should land on the same NIC. Networks sharing the same `nic_group` value are grouped together by the CPI into a single NIC with multiple IP configurations.

The CPI also sets an `alias` field (e.g. `eth0`) on the agent network settings so the bosh-agent can map both networks to the same OS interface without relying on MAC addresses (which Azure does not provide at NIC creation time).

## Prerequisites

1. **Azure virtual network with a dual-stack subnet.** The subnet must have both an IPv4 and an IPv6 address prefix configured.

   ```bash
   # Create a dual-stack VNet
   az network vnet create \
     --resource-group my-rg \
     --name boshvnet \
     --address-prefixes 10.0.0.0/16 fd00::/48

   # Create a dual-stack subnet
   az network vnet subnet create \
     --resource-group my-rg \
     --vnet-name boshvnet \
     --name dual-stack-subnet \
     --address-prefixes 10.0.0.0/24 fd00::/64
   ```

2. **VM size that supports IPv6.** Most current-generation VM sizes support dual-stack. Check the [Azure VM sizes documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes) for details.

3. **BOSH director with `nic_group` support.** The director must support RFC-0038 dual-stack networking (BOSH director PR [#2611](https://github.com/cloudfoundry/bosh/pull/2611)).

## Cloud Config

Define two separate networks (one IPv4, one IPv6) that reference the same Azure subnet:

```yaml
networks:
- name: default-ipv4
  type: manual
  subnets:
  - range: 10.0.0.0/24
    gateway: 10.0.0.1
    dns: [168.63.129.16]
    reserved: [10.0.0.1-10.0.0.3]
    cloud_properties:
      virtual_network_name: boshvnet
      subnet_name: dual-stack-subnet

- name: default-ipv6
  type: manual
  subnets:
  - range: fd00::/64
    gateway: fd00::1
    dns: [168.63.129.16]
    cloud_properties:
      virtual_network_name: boshvnet
      subnet_name: dual-stack-subnet
```

## Deployment Manifest

Reference both networks in your instance group and assign them the same `nic_group`:

```yaml
instance_groups:
- name: my-instance-group
  networks:
  - name: default-ipv4
    nic_group: "1"
    default: [dns, gateway]
  - name: default-ipv6
    nic_group: "1"
```

Both networks reference the same Azure subnet. The CPI groups them onto one NIC with two `ipConfigurations`.

## Load Balancers

For dual-stack load balancers, specify separate backend pools for IPv4 and IPv6 in your `vm_type`:

```yaml
vm_types:
- name: dual-stack-with-lb
  cloud_properties:
    instance_type: Standard_D2s_v3
    load_balancer:
      name: my-dual-stack-lb
      backend_pool_name: pool-v4
      backend_pool_name_v6: pool-v6
```

The CPI attaches the IPv4 `ipConfiguration` to `backend_pool_name` and the IPv6 `ipConfiguration` to `backend_pool_name_v6`. Application gateway pools are IPv4-only and are attached only to the primary `ipConfiguration`.

## Multi-NIC Dual-Stack

You can combine dual-stack with multiple NICs. Each NIC group gets its own `nic_group` value:

```yaml
instance_groups:
- name: multi-nic-instance
  networks:
  - name: net-v4-primary
    nic_group: "1"
    default: [dns, gateway]
  - name: net-v6-primary
    nic_group: "1"
  - name: net-v4-secondary
    nic_group: "2"
  - name: net-v6-secondary
    nic_group: "2"
```

This creates two NICs, each with an IPv4 and IPv6 `ipConfiguration`. The VM size must support the required number of NICs — see the [Azure VM sizes documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes).
