# Use Managed Disks in Cloud Foundry

## Overview

With [managed disks](https://azure.microsoft.com/en-us/blog/announcing-general-availability-of-managed-disks-and-larger-scale-sets/), you will no longer need to create storage accounts before deployment, or configure the storage account. Disk Resource Provider can arrange all disks automatically to provide best performance.

In earlier versions of CPI (up to V20), you must manually create storage accounts and then configure them in CF manifest file due to [the limitation on the number of disks per storage account](https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits). Considering best performance, every standard storage account only can host up to 40 disks and every premium storage account only can host up to 35 disks.

For better performance in a large-scale deployment, you need to create multiple storage accounts before deployment and manually configure them in every resource pools in the manifest. This is very painful. Managed Disks will hide these complexities and free the users from the need to be aware of the limitations associated with storage account. We recommend you utilize Managed Disks in your CF deployment by default.

## Changed Manifest Configuration

When you decide to enable managed disks, you need to update the [global properties](http://bosh.io/docs/azure-cpi.html#global), [resource_pools/cloud_properties](http://bosh.io/docs/azure-cpi.html#resource-pools) and [disk_pools/cloud_properties](http://bosh.io/docs/azure-cpi.html#disk-pools).

## New Deployment

Below are behavior changes with a new deployment:

1. In Azure environment preparing stage, you no longer need to create or add storage account when creating/attaching a new disk. So, **you must not specify storage_account_name in bosh.yml for a new deployment.**

1. When deploying BOSH, you need to specify additional parameters in `bosh.yml`:

    ```
    azure:
      use_managed_disks: true # New parameter, Default value is false. If the region does not support managed disks, CPI throws an error when this value is set to true.

    disk_pools:
      cloud_properties:
        storage_account_type # New parameter: Standard_LRS or Premium_LRS.
    ```

1. When deploying Cloud Foundry, you need to specify additional parameters in your CF manifest:

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

    The reason: When `use_managed_disks` is `true`, the default value of `platform_fault_domain_count` is `2` because [the maximum number of fault domain is 2 in some regions](#with-availability-sets).

## Migrating an Existing Deployment

### Before the Migration

You should **NOT** migrate the deployment if any of the following conditions is true. You should leave `use_managed_disks` as `false` in the manifest file in this case.

  * The region does not support managed disks. You can see [Azure Products by Region](https://azure.microsoft.com/en-us/regions/services/) for the availability of the Managed Disks feature.

  * If Storage Service Encryption (SSE) is enabled once, migration to managed disks is not supported. Even if SSE is disabled later, you still can't migrate to managed disks. Please see details [here](https://docs.microsoft.com/en-us/azure/storage/storage-managed-disks-overview#managed-disks-and-encryption).

You need to review the following checklist to prevent predictable migration failures.

  * The default storage account is used to store stemcells uploaded by CPI. In CPI v20 or older, it's specified by `azure.storage_account_name` in the global configurations. In CPI v20+, this property is optional. However, in the migration scenario, please make sure the default storage account is specified by `azure.storage_account_name` in the global configurations. Otherwise, CPI won't find your default storage account, which causes that all the uploaded stemcells can't be re-used.

  * The maximum number of fault domains of managed availability sets varies by region - either two or three managed disk fault domains per region. The [table](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/manage-availability#use-managed-disks-for-vms-in-an-availability-set) shows the number per region. If your existing deploymeng is using 3 fault domains, you need to check whether the region supports 3 managed disk fault domains. Please see details [here](#with-availability-sets).

  * Unmanaged snapshots cannot be migrated to managed version, and it may cause migration failure, so you need to delete all snapshots and disable snapshots in `bosh.yml` before the migration, if you enabled snapshots in the existing deployment. You can enable snapshots after full migration if you want.

    1. Disable snapshot in `bosh.yml`

        ```
        director:
          enable_snapshots: false
        ```

    1. Re-deploy BOSH director

        ```
        bosh-init deploy ~/bosh.yml
        ```

    1. Delete all existing snapshots.

### Full migration

This is the recommended approach for existing deployment, you can migrate entire deployment to managed disk with following steps:

1. In `bosh.yml`, specify the new CPI version and add below properties.

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

    >NOTE: Since an existing CF deployment has a default storage account which contains uploaded stemcells, you need to keep `azure.storage_account_name` in the global configurations in `bosh.yml` while migrating. CPI will re-use the uploaded stemcells. After the migration, you can remove the default storage account from `bosh.yml`.

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

    In this step, all VMs will be re-created with managed disks and all disks will be migrated to managed disks.

### After the Migration

If the migration is successful and your applications work as you expected, you should cleanup resources manually.

#### Delete unused persistent data disks

Delete all blobs in the container `bosh` with below tags whose names start with `bosh-data` in all storage accounts in the resource group.

```
{
  `user_agent`=>`bosh`,
  `migrated`=>`true`
}
```

#### Delete unused storage accounts

Delete all storage accounts **without** below tags in the resource group. Please do not delete those storage accounts which may be used by others (e.g. the storage account is used as a blobstore via fog).

```
{
  `user-agent`=>`bosh`,
  `type`=>`stemcell`
}
```

### More Migration Scenarios

#### With availability sets

Only managed availability set can host VMs with managed disks. However, [the maximum number of fault domains of managed availability sets varies by region - either two or three managed disk fault domains per region.](https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-manage-availability#configure-multiple-virtual-machines-in-an-availability-set-for-redundancy)

By default, CPI will migrate the old unmanaged availability sets into managed availability sets automatically, and during the migration, the fault domain number can't be changed. However due to the deployment schedule, the new managed availability set may not support the same maximum number of fault domain as the old unmanaged availability set; in this case, the migration might be blocked. You need to wait till the region supports the same maximum number of fault domains.

Let's assume that the fault domain number is set to `3` in your existing deployment.

* For the regions which support 3 FDs, the migration will succeed.
* For the regions which only support 2 FDs
  * If the existing deployment doesn't use load balancer, the migration will secceed. You need to specify a new availability set name in `resource_pools`. Then CPI will create new VMs with managed disks in new availability sets (managed) one by one. After migration, you can delete the old unmanaged availability sets manually.
  * If the existing deployment is using load balancer, the migration will fail because the VMs behind a load balancer have to be in a same availability set. This prevents CPI creating VMs in the new availability set one by one. You should not use managed disks feature until the region supports 3 FDs.

#### The default storage account's location is different from the resource group location

Before the migration, you need to do:

1. Create a new storage account in the resource group location, and create two containers `bosh` and `stemcell`, and one table `stemcells`.
1. Copy all uploaded stemcells from the container `stemcell` of the old storage account to the new one.
1. Copy all the data in the table `stemcells` of the old storage account to the new one.

>**Note**: If you use [fog](https://docs.cloudfoundry.org/deploying/common/cc-blobstore-config.html#fog-azure) with the old storage account, the blobs will still be stored in the old storage account.
