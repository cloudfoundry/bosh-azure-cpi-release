# Use Managed Disks in Cloud Foundry

## Overview

With [managed disks](https://azure.microsoft.com/en-us/blog/announcing-general-availability-of-managed-disks-and-larger-scale-sets/), you will no longer need to create storage accounts before deployment, or configure the storage account. Disk Resource Provider can arrange all disks automatically to provide best performance.

In earlier versions of CPI (up to V20), you must manually create storage accounts and then configure them in CF manifest file due to [the limitation on the number of disks per storage account](https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits). Considering best performance, every standard storage account only can host up to 40 disks and every premium storage account only can host up to 35 disks.

For better performance in a large-scale deployment, you need to create multiple storage accounts before deployment and manually configure them in every resource pools in the manifest. This is very painful. Managed Disks will hide these complexities and free the users from the need to be aware of the limitations associated with storage account.

Below issues are fixed with managed disk.

* [#228: Can we support managed disks?](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/228)
* [#225: Stripe storage account placement across each VM in an availability set](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/225)
* [#178: Avoid using storage account tables to keep track of copying process](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/178)
* [#116: user should be able to set storage_account_name on a persistent disk](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/116)
* [#68: CID of VMs is not well named](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/68)

## Changed Manifest Configuration

When you decide to enable managed disks, you need to update the [global properties](http://bosh.io/docs/azure-cpi.html#global), [resource_pools/cloud_properties](http://bosh.io/docs/azure-cpi.html#resource-pools) and [disk_pools/cloud_properties](http://bosh.io/docs/azure-cpi.html#disk-pools).

## New Deployment

Below are behavior changes with a new deployment:

1. In Azure environment preparing stage, you no longer need to create or add storage account when creating/attaching a new disk.

1. When deploying BOSH, you need to specify additional parameters:

  ```
  azure:
    use_managed_disks: true # New parameter, Default value is false. If the region does not support managed disks, CPI throws an error when this value is set to true.

  disk_pools:
    cloud_properties:
      storage_account_type # New parameter: Standard_LRS or Premium_LRS.
  ```

1. When deploying Cloud Foundry, you need to specify additional parameters:

  ```
  disk_pools:
    cloud_properties:
      storage_account_type # New parameter: Standard_LRS or Premium_LRS.
  ```

1. If availability sets are used to host VMs with managed disks and you want to have 3 fault domains, you need to set `platform_fault_domain_count` to `3` explicitly.

  ```
  resource_pools:
    cloud_properties:
      platform_fault_domain_count: 3
  ```

  The reason: When `use_managed_disks` is `true`, the default value of `platform_fault_domain_count` is `2` because [the maximum number of fault domain is 2 in some regions](#with-avset).

## Upgrading an Existing Deployment

CPI does not migrate snapshots. you need to delete all snapshots and disable snapshots in `bosh.yml` before migration, if you enabled snapshots in the existing deployment. You can enable snapshots after full migration if you want.

  1. Disable snapshot in `bosh.yml`

  1. Re-deploy BOSH director

    ```
    bosh-init deploy ~/bosh.yml
    ```

  1. Delete all existing snapshots.

For existing deployment, you can upgrade to new CPI version with a full migration. After that, you can [manually delete the original resources](#manual-cleanup).

### Full migration

This is the recommended approach for existing deployment, you can migrate entire deployment to managed disk with following steps:

1. In `bosh.yml`, specify the new CPI version and add below properties. Since an existing CF deployment has a default storage account which contains uploaded stemcells, it is better to keep it in bosh.yml for migration. After migration, you can remove the default storage account from `bosh.yml`.

  ```
  azure:
    use_managed_disks: true

  disk_pools:
    cloud_properties:
      storage_account_type # New parameter: Standard_LRS or Premium_LRS

  resource_pools:
    cloud_properties:
      storage_account_name # Remove it if it exists
      storage_account_max_disk_number # Remove it if it exists
      storage_account_type # Remove it if it exists
  ```

1. Re-deploy BOSH director

  ```
  bosh-init deploy ~/bosh.yml
  ```

1. Update your CF manifest, add below properties

  ```
  disk_pools:
    cloud_properties:
      storage_account_type

  resource_pools:
    cloud_properties:
      storage_account_name # Remove it if it exists
      storage_account_max_disk_number # Remove it if it exists
      storage_account_type # Remove it if it exists
  ```

1. Use ‘bosh recreate --force’ to update your current CF deployment

In this case, all VMs will be re-created with managed disks and all disks will be migrated to managed disks.

### Backward compatibility

For regions that do not support managed disk, you can still use the original storage account approach by keeping `use_managed_disks` as false.

<a name="manual-cleanup" />
### Manual Cleanup after Migration

After a full migration, you should cleanup resources manually.

#### Delete unused persistent data disks

Delete all blobs in the container `bosh` with below tags whose names start with `bosh-data` in all storage accounts in the resource group.

```
{
  `user_agent`=>`bosh`,
  `migrated`=>`true`
}
```

#### Delete unused storage accounts

Delete all storage accounts **without** below tags in the resource group. Please do not delete those [storage accounts which may be used by others](#fog-azure).

```
{
  `user-agent`=>`bosh`,
  `type`=>`stemcell`
}
```


### More Migration Scenarios

<a name="with-avset">
#### With availability sets

Only managed availability set can host VMs with managed disks. [The maximum number of fault domains of managed availability sets varies by region - either two or three managed disk fault domains per region.](https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-manage-availability#configure-multiple-virtual-machines-in-an-availability-set-for-redundancy)

CPI will try to migrate the old unmanaged availability sets into managed availability sets automatically. During the migration, the fault domain number can't be changed. Let's assume that the fault domain number is set to **3** in your existing deployment.

* For the regions which support 3 FDs, the migration will succeed.
* For the regions which only support 2 FDs
  * If the existing deployment doesn't use load balancer, the migration will secceed. You need to specify a new availability set name in `resource_pools`. Then CPI will create new VMs with managed disks in new availability sets (managed) one by one. After migration, you can delete the old unmanaged availability sets manually.
  * If the existing deployment is using load balancer, the migration will fail because the VMs behind a load balancer have to be in a same availability set. This prevents CPI creating VMs in the new availability set one by one. You should not use managed disks feature until the region supports 3 FDs.

#### The default storage account's location is different from the resource group location

Before the migration, you need to do:

1. Create a new storage account in the resource group location, and create two containers `bosh` and `stemcell`, and one table `stemcells`.
1. Copy all uploaded stemcells from the container `stemcell` of the old storage account to the new one.
1. Copy all the data in the table `stemcells` of the old storage account to the new one.

<a name="fog-azure"/>
>**Note**: If you use [fog with the old storage account](https://docs.cloudfoundry.org/deploying/common/cc-blobstore-config.html#fog-azure), the blobs will still be stored in the old storage account.
