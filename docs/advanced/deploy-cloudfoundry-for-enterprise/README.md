# Deploy Cloud Foundry using multiple storage accounts and availability sets

This document provides additional configuration options for high availability and performance of your Cloud Foundry infrastructure. You can configure these advanced settings at your initial deployment, or at ongoing deployment.

For basic Cloud Foundry deployment steps, please check the section [**Get Started**](../../guidance.md#get-started).
 
## Availability Set

### Why

For high availability of your Cloud Foundry infrastructure, you can utilize Availability Set for each of your resource pools.

There are two types of Microsoft Azure platform events that can affect the availability of your virtual machines: planned maintenance and unplanned maintenance. To reduce the impact of downtime due to one or more of these events, we recommend configuring multiple virtual machines in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/) for redundancy.

### How

1. Open your manifest, and configure an availability set into your `resource_pools`.

  ```
  - name: resource_router
    network: default
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      availability_set: <availability-set-name>
      instance_type: Standard_D1
  ```

  If `<availability-set-name>` does not exist, it will be created automatically.

1. Specify the resource_pool as `resource_router` in your job. Then these 2 VMs will be put into the availability set `<availability-set-name>`.

  ```
  - name: router_z1
    instances: 2
    resource_pool: resource_router
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

## Multiple Storage Accounts

### Why

By default there is one Standard Tier storage account created for each resource pool, providing 40 highly utilized disks with maximum 20,000 IOPS (See [Azure Storage Limits](https://azure.microsoft.com/en-us/documentation/articles/azure-subscription-service-limits/#storage-limits)). When you need more highly utilized disks, you need multiple storage accounts. In addition, since each resource pool can only contain single storage account, with multiple storage accounts, you also need to split the resource pool into multiple resource pools, each with a single storage account.

>**NOTE:** You can select different types of storage accounts when considering performance optimization. For example, if you need high-performance, low-latency disk support, you can also use [Azure Premium Storage](https://azure.microsoft.com/en-us/documentation/articles/storage-premium-storage-preview-portal/). Keep in mind maximum number of highly utilized disks per storage account is about 31 for Premium Storage.

### How

1. Decide whether you need multiple storage accounts and how many of them.

  Since one standard storage account can hold up to 40 highly utilized disks, if your deployment requires less than 40 disks, there is no need for multiple storage accounts. If you need more than 40 disks, then you need one additional standard storage account for every additional 40 disks. Please note, by default, one disk is created for one single VM, however you can also increase the number of disks per VM based on your need. For example, if your deployment has 80 runners (DEAs), and assuming you need 1 disk for each VM, then the total number of disks is 80. Therefore you need 2 standard storage accounts, and hence 2 resource pools.

1. Specify an additional storage account in each of the resource pools. Please make sure the storage account name is **unique within Azure** and **must be between 3 and 24 characters in length and use numbers and lower-case letters only**.

  You can use 'azure login' to login with Azure CLI and then use 'azure storage account check <new-storage-account>' to check the availability of your new storage account name.

  If you have decided that you need multiple storage accounts, you should add the additional resource pools and specify a new storage account name for each additional resource pool.

  For example, specify storage_account_name in your resource pool as follows. Then all the VMs in the pool `resource_runner_2` will store their disks in the storage account `<new-storage-account>`.

  If the new storage account does not exist and you expect Azure CPI to create it automatically, you need to specify storage_account_type. It can be either `Standard_LRS`, `Standard_ZRS`, `Standard_GRS`, `Standard_RAGRS` or `Premium_LRS`. You can click [**HERE**](http://azure.microsoft.com/en-us/pricing/details/storage/) to learn more about the type of Azure storage account.

  You also can specify the location for the new storage account. If it is not set, the location of the default resource group will be used. For more information, see [List all of the available geo-locations](http://azure.microsoft.com/en-us/regions/). For `AzureChinaCloud`, you should only use the regions in China, `chinanorth` or `chinaeast`.

1. For best disk performance, you should use DS-series, DSv2-series, Fs-series and GS-series VMs which can use premium storage. For more information, see [Sizes for virtual machines in Azure](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-sizes/).

  ```
  - name: resource_runner_1
    network: default
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      instance_type: Standard_D1
      storage_account_name: <origin-storage-account>
  - name: resource_runner_2
    network: default
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      instance_type: Standard_DS1_v2
      storage_account_name: <new-storage-account>
      storage_account_type: Premium_LRS
      storage_account_location: eastus2
  ```

1. Please use Azure CPI v7 or later version. The new storage accounts which are specified in the `resource_pools` section will be created by Azure CPI automatically if they do not exist.

1. Deploy your Cloud Foundry with the updated manifest. You can configure multiple storage accounts for the first deployment, or for on going deployments.

Click [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/src/bosh_azure_cpi/README.md) to learn more about the configuration of availability sets and multiple storage accounts.
