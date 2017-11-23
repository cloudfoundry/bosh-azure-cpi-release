# Deploy Cloud Foundry using availability sets

>**NOTE:** CPI v33+ supports availability zones, which is a different concept than availability sets. If you want to try it, please go to the [doc](../availability-zone/).
 
This document provides additional configuration options for high availability and performance of your Cloud Foundry infrastructure. You can configure these advanced settings at your initial deployment, or at ongoing deployment.

For basic Cloud Foundry deployment steps, please check the section [**Get Started**](../../guidance.md#get-started).
 
## Why

For high availability of your Cloud Foundry infrastructure, you can utilize Availability Set for each of your resource pools.

There are two types of Microsoft Azure platform events that can affect the availability of your virtual machines: planned maintenance and unplanned maintenance. To reduce the impact of downtime due to one or more of these events, we recommend configuring multiple virtual machines in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/) for redundancy.

## How

1. Open your manifest, and configure an availability set into your `resource_pools`.

   * Specify `availability_set` in `cloud_properties`

      ```
      - name: resource_pool_with_availability_set
        network: default
        stemcell:
          name: bosh-azure-hyperv-ubuntu-trusty-go_agent
          version: latest
        cloud_properties:
          availability_set: <availability-set-name>
          instance_type: Standard_D1
      ```

    if `availability_set` is not specified in `cloud_properties`, Azure CPI will pick `env.bosh.group` as the availability set name.

    If the specified availability set does not exist, Azure CPI will create it automatically.

1. You can specify the `resource_pool` as `resource_pool_with_availability_set` in your job. Then these 2 VMs of this job will be put into the availability set `<availability-set-name>`.

    ```
    - name: router_z1
      instances: 2
      resource_pool: resource_pool_with_availability_set
      templates:
      - {name: gorouter, release: cf}
      - {name: metron_agent, release: cf}
      networks:
      - name: default
        static_ips: [10.0.16.12, 10.0.16.22]
      properties:
        ...
    ```

1. Deploy your Cloud Foundry.
