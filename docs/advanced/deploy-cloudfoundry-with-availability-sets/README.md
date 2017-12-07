# Deploy Cloud Foundry using availability sets

>**NOTE:** CPI v33+ supports availability zones, which is a different concept than availability sets. If you want to try it, please go to the [doc](../availability-zone/).
 
This document provides additional configuration options for high availability and performance of your Cloud Foundry infrastructure. You can configure these advanced settings at your initial deployment, or at ongoing deployment.

For basic Cloud Foundry deployment steps, please check the section [**Get Started**](../../guidance.md#get-started).
 
## Why

For high availability of your Cloud Foundry infrastructure, you can utilize Availability Set for each of your resource pools.

There are two types of Microsoft Azure platform events that can affect the availability of your virtual machines: planned maintenance and unplanned maintenance. To reduce the impact of downtime due to one or more of these events, we recommend configuring multiple virtual machines in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/) for redundancy.

## How

1. Add a new `vm_extension` with the property `availability_set` into your cloud config.

    ```
    vm_extensions:
    - name: availability-set-properties
      cloud_properties:
        availability_set: <availability-set-name>
    ```

    if `availability_set` is not specified, Azure CPI will pick `env.bosh.group` as the availability set name.

    If the specified availability set does not exist, Azure CPI will create it automatically.

1. You can add the vm extension `availability-set-properties` into `vm_extensions` of your instance group. Then the VMs of this instance group will be put into the availability set `<availability-set-name>`.

    1. Download the ops file [`use-availability-set.yml`](./use-availability-set.yml) to `~/use-availability-set.yml`.

    1. Add the line `-o ~/use-availability-set.yml` to the `bosh -n -d cf deploy` command in `deploy_cloud_foundry.sh`.

1. Deploy your Cloud Foundry.

    ```
    ./deploy_cloud_foundry.sh
    ```
