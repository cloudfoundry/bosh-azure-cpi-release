# Use Managed Disks in Cloud Foundry

## Overview

With [managed disks](https://azure.microsoft.com/en-us/blog/announcing-general-availability-of-managed-disks-and-larger-scale-sets/), you will no longer need to create storage accounts before deployment, or configure the storage account. Disk Resource Provider can arrange all disks automatically to provide best performance.

In earlier versions of CPI (up to V20), you must manually create storage accounts and then configure them in CF manifest file due to [the limitation on the number of disks per storage account](https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits). Considering best performance, every standard storage account only can host up to 40 disks and every premium storage account only can host up to 35 disks.

For better performance in a large-scale deployment, you need to create multiple storage accounts before deployment and manually configure them in every resource pools in the manifest. This is very painful. Managed Disks will hide these complexities and free the users from the need to be aware of the limitations associated with storage account. We recommend you utilize Managed Disks in your CF deployment by default.

## Changed Manifest Configuration

When you decide to enable managed disks, you must update the [Global Configuration](http://bosh.io/docs/azure-cpi/#global). It's optional to update [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools) and [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools) if needed.

## Configuration Reference

Enable `azure.use_managed_disks: true` in the CPI job's global properties (normally under `properties.azure` in the director deployment). This is a CPI setting, not a `vm_types` cloud property. For a director created with bosh-deployment, use the managed-disks ops file linked below.

### Choose the Disk Role

| Disk role | Where to configure it | Purpose and durability |
| --- | --- | --- |
| Root / OS disk | `vm_types[].cloud_properties.root_disk` | Holds the operating system. The default is a remote managed disk, but BOSH VM recreation replaces the OS disk. Do not use it for application data that must survive recreation. |
| BOSH ephemeral disk | `vm_types[].cloud_properties.ephemeral_disk` | Workspace for packages, logs, and temporary data. Normally a separate managed data disk; it is disposable despite using managed storage. |
| Persistent disk | `disk_types[]`, selected with an instance group's `persistent_disk_type` | Holds durable application data that BOSH can reattach to a replacement VM. It still needs backups and application-level recovery planning. |
| Azure Ephemeral OS Disk | `root_disk.placement: resource-disk`, `cache-disk`, or `nvme-disk` | Places the OS on local VM storage instead of a remote managed OS disk. This is different from the BOSH ephemeral disk. Local contents can be lost during host recovery or reimage. |

VM cloud properties can also be supplied through `vm_extensions[].cloud_properties`. Disk sizes in BOSH configuration are **MiB**, not GiB: `32768` is 32 GiB. Use integer multiples of 1024 for predictable sizing. IOPS means I/O operations per second; `mbps` is disk throughput in MB/s, not network megabits per second.

### VM Disk Settings

The following paths are relative to a VM type's or VM extension's `cloud_properties`.

| Property | Values and default | Benefit and tradeoff |
| --- | --- | --- |
| `root_disk.size` | Integer MiB; normally inherited from the stemcell when omitted. A size smaller than the stemcell is ignored. | Adds OS and package space. Larger remote disks can cost more; local OS disks must fit the VM's available local capacity. |
| `root_disk.type` | Remote disk SKU, commonly `Standard_LRS`, `StandardSSD_LRS`, or `Premium_LRS`. Takes precedence over VM-level `storage_account_type`. | Selects the OS disk's price/performance tier. Use with `placement: remote`; Premium SSD v2 and Ultra disks are not OS disk options. |
| `storage_account_type` | Fallback for the root disk type. If neither type is set, CPI selects `Premium_LRS` for a VM supporting Premium storage, otherwise `Standard_LRS`. | Provides a VM-level default for the root disk, not a default for every persistent or ephemeral disk. Despite its name, this selects a disk SKU in managed-disk mode. |
| `root_disk.placement` | `remote` (default), `resource-disk`, `cache-disk`, or `nvme-disk`. | Remote storage avoids local-capacity constraints. Local placement can reduce OS I/O latency and avoid a separately billed managed OS disk, but requires a compatible VM and disposable OS state. Use `nvme-disk` on supported v6-and-newer VM sizes with local NVMe storage. |
| `root_disk.full_caching` | Boolean, default `false`. Enabling requires `resource-disk`, `cache-disk`, or `nvme-disk` placement. | Copies the full OS image to local storage in the background. Use with managed disks enabled and an eligible VM with sufficient local capacity; this does not make OS or workspace data durable. |
| `caching` | Root disk host caching: `None`, `ReadOnly`, or `ReadWrite` (default). Local OS disks use `ReadOnly` in this CPI. | Can accelerate eligible disk I/O. This is a VM-level property, not `root_disk.caching`; see caching guidance below. |
| `root_disk.disk_encryption_set_name` | Existing Disk Encryption Set name; omitted by default. | Customer-managed encryption keys for a remote managed OS disk. Requires key access and lifecycle management; do not assume it applies to local OS storage. |
| `ephemeral_disk.size` | Integer MiB; if omitted for a separate disk, CPI uses its VM-size disk information. | Adds temporary workspace. Set it explicitly to avoid depending on a VM-specific default. |
| `ephemeral_disk.type` | Managed data disk SKU; if omitted, CPI does not send an explicit SKU and Azure chooses its default. | Allows a different tier for temporary workspace than for the OS or persistent data. |
| `ephemeral_disk.caching` | `None`, `ReadOnly`, or `ReadWrite` (default for a separate disk). | Tunes host caching independently from the OS disk. Unsupported SKU/cache combinations are rejected by Azure. |
| `ephemeral_disk.iops`, `ephemeral_disk.mbps` | Optional integers for a compatible SKU such as `PremiumV2_LRS` or `UltraSSD_LRS`. | Tunes temporary-disk performance independently of capacity. CPI applies these after VM creation; VM and disk limits still apply. See SKU limitations below. |
| `ephemeral_disk.disk_encryption_set_name` | Existing Disk Encryption Set name; omitted by default. | Customer-managed encryption keys for the separate managed ephemeral data disk. |
| `ephemeral_disk.use_root_disk` | Boolean, default `false`. | With `true`, uses the OS disk for BOSH ephemeral workspace and avoids creating a separate ephemeral data disk. Saves that disk's cost but shares OS capacity and I/O. Separate ephemeral disk type, caching, performance, and encryption settings then do not apply. |

When `use_root_disk` is `true`, explicitly size the root disk for both OS and workspace. For a remote OS disk, `ephemeral_disk.size` does not enlarge the root disk; use `root_disk.size`. For local OS placement, CPI adds a supplied `ephemeral_disk.size` to the calculated OS size. When root size is omitted, CPI's sizing also depends on the stemcell and OS, so do not assume one fixed default fits every deployment.

### Remote Managed Disk Example

Merge these entries into the corresponding lists in your BOSH cloud config; retain your existing networks and other settings. Choose an instance type available in your region.

```yaml
vm_types: [{
    name: managed-worker,
    cloud_properties: {
        instance_type: Standard_D4s_v5,
        root_disk: {placement: remote, size: 32768, type: Premium_LRS},
        caching: ReadWrite,
        ephemeral_disk: {
            size: 65536,
            type: StandardSSD_LRS,
            caching: ReadWrite,
            use_root_disk: false
        }
    }
}]

disk_types: [{
    name: application-data,
    disk_size: 131072,
    cloud_properties: {storage_account_type: Premium_LRS, caching: None}
}]
```

In the deployment manifest, select `vm_type: managed-worker` and `persistent_disk_type: application-data` on the instance group that needs persistent storage. This example separates a 32 GiB OS disk, 64 GiB temporary workspace, and 128 GiB persistent data disk so each can be sized and tuned independently.

### Persistent Disk Settings

Set `disk_size` on the disk type itself. The other properties below belong under `disk_types[].cloud_properties`, not under the VM's `root_disk` or `ephemeral_disk`.

| Property | Values and default | Benefit and tradeoff |
| --- | --- | --- |
| `disk_size` | Required integer MiB on the disk type. | Sizes durable application storage. Provisioned capacity, not just used space, affects billing. |
| `storage_account_type` | Common choices: `Standard_LRS`, `StandardSSD_LRS`, `Premium_LRS`, `PremiumV2_LRS`, `UltraSSD_LRS`, subject to Azure compatibility. | Selects price, latency, and performance characteristics. If omitted with a VM context, CPI selects Premium or Standard HDD based on VM Premium storage support; without a VM context it defaults to `Standard_LRS`. |
| `caching` | `None` (default), `ReadOnly`, or `ReadWrite`. | Controls host caching when the disk is attached. Choose according to the application and disk SKU, not just the fastest benchmark result. |
| `iops` | Optional integer; Azure's SKU default applies if omitted. Intended for Premium SSD v2 or Ultra disks. | Raises the ceiling for frequent small I/O operations, such as database random reads. Provisioning more than the VM can deliver wastes money. |
| `mbps` | Optional integer MB/s; Azure's SKU default applies if omitted. Intended for Premium SSD v2 or Ultra disks. | Raises the ceiling for large sequential transfers. Throughput and IOPS settings must satisfy Azure's disk-size and SKU constraints. |
| `disk_encryption_set_name` | Existing Disk Encryption Set name; omitted by default. | Uses customer-managed keys instead of the default platform-managed keys for encryption at rest. This improves key governance, not disk throughput. |

Persistent disks created for a VM inherit its resource group, location, and availability zone. Without a VM context they use the CPI's default resource group and its location, with no explicit zone. `zone`, `availability_zone`, and `resource_group_name` are not overrides read from persistent disk cloud properties by this creation path. Configure VM placement with `availability_zone` (or BOSH AZ cloud properties); do not combine a VM availability zone with an availability set.

For example, this disk type requests 128 GiB with independently provisioned performance. It requires a Premium SSD v2-compatible VM and supported region/zone; it is not an OS disk configuration.

```yaml
disk_types: [{
    name: database-v2,
    disk_size: 131072,
    cloud_properties: {
        storage_account_type: PremiumV2_LRS,
        caching: None,
        iops: 6000,
        mbps: 250
    }
}]
```

### Select a Storage Tier

| SKU | Typical use and improvement | Main consideration |
| --- | --- | --- |
| `Standard_LRS` | HDD storage for infrequent, latency-tolerant access. | Lower performance and less consistent latency than SSDs; do not rely on the CPI default as a production performance recommendation. |
| `StandardSSD_LRS` | General-purpose or development workloads needing more consistent latency than HDDs. | Lower performance ceilings than Premium options; include transaction charges when estimating cost. |
| `Premium_LRS` | Production workloads needing predictable SSD performance and low latency. | Requires a compatible VM. Capacity tiers determine baseline performance; increasing disk size may buy performance as well as space. |
| `PremiumV2_LRS` | Data disks needing low latency with capacity, IOPS, and throughput tuned separately. | No OS disk use or host caching. Check region, zone, and VM support; performance above the included baseline costs extra. |
| `UltraSSD_LRS` | Very demanding data-disk workloads requiring high provisioned IOPS and throughput. | No OS disk use, host caching, or availability sets. Requires Ultra-enabled VM support and has additional deployment restrictions. |

These are not interchangeable SKUs. In particular, accepting an Ultra disk SKU in disk parameters does not automatically enable Ultra capability on a VM. This CPI's VM creation payload does not set `additionalCapabilities.ultraSSDEnabled`; verify the complete VM enablement path before planning an Ultra deployment. No working Ultra VM example is implied here.

The `_LRS` suffix means locally redundant storage, not replication across availability zones. A zonal VM and its LRS disks do not by themselves provide cross-zone application availability. Azure also offers ZRS disk SKUs, but the table above is not a promise that every Azure disk feature or redundancy mode is supported by every CPI workflow.

Check current [Azure disk types and restrictions](https://learn.microsoft.com/azure/virtual-machines/disks-types), [VM and disk performance limits](https://learn.microsoft.com/azure/virtual-machines/disks-performance), and [managed disk pricing](https://azure.microsoft.com/pricing/details/managed-disks/) before choosing sizes or throughput targets. Azure limits and availability can differ across public regions, sovereign clouds, and Azure Stack. Extra disk performance cannot overcome the VM's aggregate disk I/O limit.

### Host Caching

| Mode | Effect | When to consider it |
| --- | --- | --- |
| `None` | Bypasses the VM host disk cache. | A conservative starting point for durable data, write-heavy logs, and applications that require uncached storage. Required for Premium SSD v2 and Ultra disks. |
| `ReadOnly` | Caches reads while writes go to the backing disk. | Read-heavy data on supported SKUs, where cache hits can reduce latency and remote reads. The disk is still writable. |
| `ReadWrite` | Enables host read and write caching. | OS and disposable workspace workloads on supported SKUs. Use for durable application data only when the application's flushing and durability requirements are compatible with Azure host caching. |

Caching is not a backup or a durability guarantee. Measure the real workload, including cache misses and sustained I/O, before changing it. See [Azure disk performance and caching](https://learn.microsoft.com/azure/virtual-machines/disks-performance).

### Local OS Disks and Full Caching

For a stateless worker with a suitable local-storage VM, the following VM cloud properties place the OS on the resource disk and use it for BOSH workspace:

```yaml
cloud_properties: {
    instance_type: Standard_D8ds_v5,
    root_disk: {placement: resource-disk, size: 65536},
    ephemeral_disk: {use_root_disk: true}
}
```

Use `cache-disk` instead only on a VM size supporting cache placement. Omit `root_disk.type` for local placement examples. Verify the final OS size, stemcell, local capacity, and any space reserved for security features before deployment.

For supported **v6 and newer VM series with local NVMe storage**, use `nvme-disk`. CPI maps this value to Azure's `NvmeDisk` placement. For example:

```yaml
cloud_properties: {
    instance_type: Standard_D2ads_v6,
    root_disk: {placement: nvme-disk, size: 65536},
    ephemeral_disk: {use_root_disk: true}
}
```

NVMe placement uses the VM's local NVMe storage for the ephemeral OS disk, providing low-latency I/O for stateless OS and workspace workloads. Actual performance depends on the VM's local storage capabilities, not the placement name alone. The final OS disk must fit the available NVMe capacity. Azure allocates whole local NVMe disks to the OS, so unused capacity on an allocated NVMe disk is not returned as a separate temporary disk.

The v6 designation refers to the **VM size series**, not the stemcell's Hyper-V generation. Not every v6-or-newer size includes local NVMe storage or supports this placement. Check the chosen SKU, region, image compatibility, and [Azure NVMe placement requirements](https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks#placement-options-for-ephemeral-os-disks). NVMe placement does not enable full caching automatically; the small VM example above is not a full-caching example.

Local OS placement can improve latency and reimage speed. The tradeoff is loss of OS/workspace contents during reimage, redeploy, or host recovery; Azure also restricts operations such as stop/deallocate and OS disk snapshots. Keep durable state on a separate persistent disk or external service. See [Ephemeral OS disk limitations](https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks).

Azure's `diffDiskSettings.enableFullCaching` is separate from the `None`/`ReadOnly`/`ReadWrite` host caching modes. Full caching copies the entire OS image to local storage in the background, reducing steady-state remote-storage dependence and improving resilience to remote storage interruptions. It does not make local data persistent.

Set `root_disk.full_caching: true` in the VM's cloud properties to enable full caching. It defaults to `false` when omitted. Use YAML booleans `true` or `false`, not quoted strings. Enabling requires an explicit `resource-disk`, `cache-disk`, or `nvme-disk` placement; `remote` or omitted placement is rejected when full caching is enabled. The CPI sends the boolean as `diffDiskSettings.enableFullCaching` and keeps local OS disk caching at `ReadOnly`.

Enable `azure.use_managed_disks: true` in the CPI's global configuration before using this setting. Full caching requires Compute API `2025-04-01` or later, an eligible VM SKU with at least 8 vCPUs, and local storage greater than twice the final OS disk size plus 1 GiB. Include any workspace size added by `ephemeral_disk.size` when calculating that requirement. Check the [current full-caching prerequisites](https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks#full-caching-mode-for-ephemeral-os-disks) for supported VM families, regions, and image compatibility; CPI property validation does not verify these Azure prerequisites.

For example, enable full caching for a 64 GiB OS disk and shared BOSH workspace on an eligible resource-disk VM:

```yaml
cloud_properties: {
    instance_type: Standard_D8ds_v5,
    root_disk: {placement: resource-disk, size: 65536, full_caching: true},
    ephemeral_disk: {use_root_disk: true}
}
```

This example requires more than 129 GiB of available local capacity. Verify the selected size and stemcell in your target region before deployment. Full caching is populated asynchronously after boot, so its steady-state benefits are not immediate. OS and workspace contents remain disposable.

### Customer-Managed Encryption Keys

Azure managed disks are encrypted at rest with platform-managed keys by default. Use `disk_encryption_set_name` only when you need control over the key. Create the Disk Encryption Set and its Key Vault key first, grant the set's managed identity the required key permissions, and grant the CPI identity permission to use the set. Follow Azure's [customer-managed key prerequisites](https://learn.microsoft.com/azure/virtual-machines/disk-encryption).

This CPI resolves the supplied set name in the **globally configured CPI resource group**, including when the VM or disk is in another resource group. The property takes a name, not a resource ID. Ensure location and other Azure compatibility requirements are met. Set the property independently on the root disk, separate ephemeral disk, and persistent disk if all three must use customer-managed keys. Losing or revoking access to the key can make disk data unavailable; plan key rotation and recovery accordingly.

### Apply Changes Safely

1. Enable managed disks in the director's CPI configuration, then update cloud config with `bosh update-cloud-config PATH_TO_CLOUD_CONFIG` and deploy the manifest selecting the VM and disk types.
2. Test changes on a non-production instance group. Review BOSH's deployment plan: VM disk configuration changes can recreate VMs and discard OS and ephemeral contents.
3. Back up persistent data before changing size, SKU, encryption, or placement. Native managed-disk update supports growth, SKU, IOPS, and throughput changes subject to Azure constraints; it rejects shrinking and caching changes and does not update the Disk Encryption Set. Whether BOSH uses native update or disk migration depends on director/CPI support and the requested change. Do not assume an in-place or zero-downtime operation.
4. Verify the resulting Azure disk SKU, size, caching, encryption, and zone, then measure latency, IOPS, throughput, and throttling under representative load. Retain a tested application recovery procedure.

## New Deployment

Below are behavior changes with a new deployment:

1. Before the deployment, you no longer need to create or add storage account. So, **it is not required to specify storage_account_name in bosh.yml for a new deployment.**

1. Deploying BOSH director:

    1. (**REQUIRED**) You need to enable managed disks in the [Global Configuration](http://bosh.io/docs/azure-cpi/#global) using the ops file [use-managed-disks.yml](https://raw.githubusercontent.com/cloudfoundry/bosh-deployment/master/azure/use-managed-disks.yml).

    1. (Optional) You can specify the `storage_account_type` in [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools). For example, if you need a SSD persistent disk for the BOSH director, you can use `Premium_LRS`.

1. Deploying Cloud Foundry:

    1. (Optional) If availability sets are used to host VMs with managed disks and you want to have 3 fault domains, you need to set `platform_fault_domain_count` to `3` explicitly in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). The reason: When `use_managed_disks` is `true`, the default value of `platform_fault_domain_count` is `2` because [the maximum number of fault domain is 2 in some regions](#with-availability-sets).

    1. (Optional) You can specify the `storage_account_type` in [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools). For example, if you need a SSD persistent disk for Cloud Foundry VM, you can use `Premium_LRS`.

## Migrating an Existing Deployment

### Before the Migration

You need to review the following checklist to prevent predictable migration failures.

  * The default storage account is used to store stemcells uploaded by CPI. In CPI v20 or older, it's specified by `azure.storage_account_name` in the global configurations. In CPI v20+, this property is optional. However, in the migration scenario, please make sure the default storage account is specified by `azure.storage_account_name` in the global configurations. Otherwise, CPI won't find your default storage account, which causes that all the uploaded stemcells can't be re-used.

  * As of CPI v52.0.0, the maximum number of fault domains of managed availability sets will be configured to the maximum fault domains supported by the region or the currently configured value for the availability set, whichever is lower. CPI versions before this will fail if the region does not support the number of fault domains currently configured on the availability set and you will first need to manually adjust the fault domain count in Azure.

  * Unmanaged snapshots cannot be migrated to managed version, and it may cause migration failure, so you need to delete all snapshots and disable snapshots in `bosh.yml` before the migration, if you enabled snapshots in the existing deployment. You can enable snapshots after full migration if you want.

    1. Disable snapshot in `bosh.yml`

        ```
        director:
          enable_snapshots: false
        ```

    1. Re-deploy BOSH director

        ```
        bosh create-env ~/bosh.yml
        ```

    1. Delete all existing snapshots.

### Full migration

This is the recommended approach for existing deployment, you can migrate entire deployment to managed disk with following steps:

1. Update the manifest for deploying BOSH director:

    1. (**REQUIRED**) Upgrade Azure CPI to the new version.

    1. (**REQUIRED**) You need to enable managed disks in the [Global Configuration](http://bosh.io/docs/azure-cpi/#global) using the ops file [use-managed-disks.yml](https://raw.githubusercontent.com/cloudfoundry/bosh-deployment/master/azure/use-managed-disks.yml).

    1. (**REQUIRED**) You need to remove `storage_account_name` and `storage_account_max_disk_number` if they exist in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools).

    1. (Optional) You can specify the `storage_account_type` in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). For example, if you need a SSD root disk for the BOSH director, you can use `Premium_LRS`.

    1. (Optional) You can specify the `storage_account_type` in [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools). For example, if you need a SSD persistent disk for the BOSH director, you can use `Premium_LRS`.

    1. (Optional) You can specify the `iops` and `mbps` properties in [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools) if `storage_account_type` is either `PremiumV2_LRS` or `UltraSSD_LRS`. For more information, read [Premium SSD v2 performance](https://learn.microsoft.com/azure/virtual-machines/disks-types#premium-ssd-v2-performance) or [Ultra disk performance](https://learn.microsoft.com/azure/virtual-machines/disks-types#ultra-disk-performance).

    >NOTE: Since an existing CF deployment has a default storage account which contains uploaded stemcells, you need to keep `azure.storage_account_name` in the global configurations in `bosh.yml` while migrating. CPI will re-use the uploaded stemcells. After the migration, you can remove the default storage account from `bosh.yml`.

1. Re-deploy BOSH director

    ```
    bosh create-env ~/bosh.yml
    ```

1. Update the manifest for deploying Cloud Foundry:

    1. (**REQUIRED**) You need to remove `storage_account_name` and `storage_account_max_disk_number` if they exist in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools).

    1. (Optional) If availability sets are used to host VMs with managed disks and you want to have 3 fault domains, you need to set `platform_fault_domain_count` to `3` explicitly in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). The reason: When `use_managed_disks` is `true`, the default value of `platform_fault_domain_count` is `2` because [the maximum number of fault domain is 2 in some regions](#with-availability-sets).

    1. (Optional) You can specify the `storage_account_type` in [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). For example, if you need a SSD root disk for Cloud Foundry VM, you can use `Premium_LRS`.

    1. (Optional) You can specify the `storage_account_type` in [Disk Types](http://bosh.io/docs/azure-cpi/#disk-pools). For example, if you need a SSD persistent disk for Cloud Foundry VM, you can use `Premium_LRS`.


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

As of CPI version v52.0.0, if the availability set is configured with a higher fault domains count than the region supports, the availability set will be migrated to match the lower number supported by the region.

#### The default storage account's location is different from the resource group location

Before the migration, you need to do:

1. Create a new storage account in the resource group location, and create two containers `bosh` and `stemcell`, and one table `stemcells`.
1. Copy all uploaded stemcells from the container `stemcell` of the old storage account to the new one.
1. Copy all the data in the table `stemcells` of the old storage account to the new one.

>**Note**: If you use [fog](https://docs.cloudfoundry.org/deploying/common/cc-blobstore-config.html#fog-azure) with the old storage account, the blobs will still be stored in the old storage account.
