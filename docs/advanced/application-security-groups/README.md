# Use Application Security Groups in Cloud Foundry

## Overview

[Application Security Groups](https://docs.microsoft.com/en-us/azure/virtual-network/security-overview#application-security-groups) enable you to configure network security as a natural extension of an application’s structure, allowing you to group virtual machines and define network security policies based on those groups. Application Security Group (ASG) has to work with Network Security Group (NSG). You can [create a network security group with application security groups](https://docs.microsoft.com/en-us/azure/virtual-network/create-network-security-group-preview).

## Pre-requirements

Before using ASG with Cloud Foundry, you need to:

1. create the ASGs you need.

1. create all the ASG-based rules in NSG.

1. specify the NSG name in the `cloud_properties` of [`vm_extensions`](https://bosh.io/docs/azure-cpi.html#resource-pools) or [`Networks`](https://bosh.io/docs/azure-cpi.html#networks). This step remains same as before.

## Manifest Configurations

You have two ways to specify the ASGs and NSG.

1. You would specify the ASGs in the [`cloud_properties` of `vm_extensions`](https://bosh.io/docs/azure-cpi.html#resource-pools).

    ```
    vm_extensions:
    - name: application-security-group-properties
      cloud_properties:
        application_security_groups: ["asg-name-1", “asg-name-2”]
    ```

    Any instance/VM with this extension will be grouped into the ASGs. For example, the VM with the extension “application-security-group-properties” belongs to two ASGs "asg-name-1" and “asg-name-2”.

1. You would specify the ASGs in the `cloud_properties` of `networks`.

    ```
    networks:
    - name: default
      type: manual
      subnets:
      - range: 10.10.0.0/24
        gateway: 10.10.0.1
        cloud_properties:
          resource_group_name: my-resource-group
          virtual_network_name: boshnet
          subnet_name: boshsub
          security_group: my-network-security-group
      application_security_groups: ["asg-name-1", “asg-name-2”]
    ```

    Any instance/VM in the network will be grouped into the ASGs. If ASGs are specified in the networks and vm_extensions, the ASGs of vm_extensions have the high priority.
