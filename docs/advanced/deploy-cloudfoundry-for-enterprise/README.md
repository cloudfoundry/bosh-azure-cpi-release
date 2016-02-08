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

2. Specify the resource_pool as `resource_router` in your job. Then these 2 VMs will be put into the availability set `<availability-set-name>`.

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
      dropsonde: {enabled: true}
  ```

3. Deploy your Cloud Foundry.

## Multiple Storage Accounts

### Why

By default there is one Standard Tier storage account created for each resource pool, providing 40 highly utilized disks with maximum 20,000 IOPS (See [Azure Storage Limits](https://azure.microsoft.com/en-us/documentation/articles/azure-subscription-service-limits/#storage-limits)). When you need more highly utilized disks, you need multiple storage accounts. In addition, since each resource pool can only contain single storage account, with multiple storage accounts, you also need to split the resource pool into multiple resource pools, each with a single storage account.

>**NOTE:** You can select different types of storage accounts when considering performance optimization. For example, if you need high-performance, low-latency disk support, you can also use [Azure Premium Storage](https://azure.microsoft.com/en-us/documentation/articles/storage-premium-storage-preview-portal/). Keep in mind maximum number of highly utilized disks per storage account is about 31 for Premium Storage.

### How

1. Decide whether you need multiple storage accounts and how many of them.

  Since one standard storage account can hold up to 40 highly utilized disks, if your deployment requires less than 40 disks, there is no need for multiple storage accounts. If you need more than 40 disks, then you need one additional standard storage account for every additional 40 disks. Please note, by default, one disk is created for one single VM, however you can also increase the number of disks per VM based on your need. For example, if your deployment has 80 runners (DEAs), and assuming you need 1 disk for each VM, then the total number of disks is 80. Therefore you need 2 standard storage accounts, and hence 2 resource pools.

2. Specify an additional storage account in each of the resource pools.

  If you have decided that you need multiple storage accounts, you should add the additional resource pools and specify a new storage account name for each additional resource pool.

  For example, specify `storage_account_name: <new-storage-account>` in your resource pool as follows. Then all the VMs in the pool `resource_runner_2` will store their disks in the storage account `<new-storage-account>`.

  ```
  - name: resource_runner_1
    network: default
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      storage_account_name: <origin-storage-account>
      instance_type: Standard_D1
  - name: resource_runner_2
    network: default
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      storage_account_name: <new-storage-account>
      instance_type: Standard_D1
  ```

3. Create the new storage accounts which are specified in the `resource_pools` section, if they do not exist.

  Create `<new-storage-account-name>`.

  ```
  azure storage account create --location <location> --type <account-type> --resource-group <resource-group-name> <new-storage-account-name>
  ```

  Create storage containers `bosh` and `stemcell` in `<new-storage-account-name>`.

  ```
  azure storage account keys list --resource-group <resource-group-name> <new-storage-account-name> # Get your storage account key
  azure storage container create --account-name <new-storage-account-name> --account-key <storage-account-key> bosh
  azure storage container create --account-name <new-storage-account-name> --account-key <storage-account-key> stemcell
  ```

  For more information about how to create storage accounts and storage containers, click [**HERE**](./deploy-bosh-manually.md#setup-a-default-storage-account).

4. Deploy your Cloud Foundry with the updated manifest. You can configure multiple storage accounts for the first deployment, or for on going deployments.

## Example Deployment

Below is an example manifest for deploying Cloud Foundry with availability sets and multiple storage accounts. 

* [**cf-for-enterprise-224.yml**](./cf-for-enterprise-224.yml)

The deployment includes a typical scenario with 21 VMs and additional 13 storage accounts. There is a specific resource pool for each job. And for each resource pool, an availability set and a unique storage account are specified. Due to the disk needs of runners, 2 resource pools are configured. You can adjust the number of resource pools based on your needs.

```
+----------------------------------+-----------------------------------------+------------------+-----------------+-----------+
| Job                              | Resource Pool                           | Availability Set | Storage Account | Instances |
+----------------------------------+-----------------------------------------+------------------+-----------------+-----------+
| api_z1                           | cloud_controller-partition              | cloudcontroller  | cc              | 2         |
| doppler_z1                       | doppler-partition                       | doppler          | doppler         | 2         |
| etcd_z1                          | etcd_server-partition                   | etcd             | etcdserver      | 1         |
| ha_proxy_z1                      | ha_proxy-partition                      | haproxy          | haproxy         | 1         |
| hm9000_z1                        | health_manager-partition                | healthmanager    | healthmanager   | 2         |
| loggregator_trafficcontroller_z1 | loggregator_trafficcontroller-partition | loggregator      | loggregator     | 2         |
| nats_z1                          | nats-partition                          | nats             | nats            | 1         |
| nfs_z1                           | nfs_server-partition                    | nfs              | nfsserver       | 1         |
| postgres_z1                      | postgres-partition                      | postgres         | postgres        | 1         |
| router_z1                        | router-partition                        | router           | router          | 1         |
| router_z2                        | router-partition                        | router           | router          | 1         |
| runner_z1                        | runner-partition-1                      | runner           | runner1         | 2         |
| runner_z2                        | runner-partition-2                      | runner           | runner2         | 2         |
| uaa_z1                           | uaa-partition                           | uaa              | uaa             | 2         |
+----------------------------------+-----------------------------------------+------------------+-----------------+-----------+
```

Click [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/src/bosh_azure_cpi/README.md) to learn more about the configuration of availability sets and multiple storage accounts.
