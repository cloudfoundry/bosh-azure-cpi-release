# Calculate the VM Cloud Properties

The deployment manifest supports a new feature `vm_resources` in the [instance groups block](https://bosh.io/docs/manifest-v2.html#instance-groups). The feature is based on a CPI method [`calculate_vm_cloud_properties`](https://bosh.io/docs/cpi-api-v1.html#calculate-vm-cloud-properties) which is available in Azure CPI [`v33+`](https://github.com/cloudfoundry/bosh-azure-cpi-release/releases/tag/v33).

The format of `vm_resources`:

```
vm_resources:
  cpu: <number-of-CPUs>
  ram: <amount-of-RAM-in-MB>
  ephemeral_disk_size: <ephemeral-disk-size-in-MB>
```

The returned Azure specific cloud properites contain two parts: `instance_type` and `ephemeral_disk`.

```
{
  'instance_type' => '<VM-SIZE>',
  'ephemeral_disk' => {
    'size' => '<DISK-SIZE>'
  }
}
```

## How to enable the feature

1. Specify the `location` in the [global configuration](https://bosh.io/docs/azure-cpi.html#global).

1. Redeploy the BOSH director.

1. Specify `vm_resources` and remove `vm_type` in the instance group block. e.g.

    ```diff
    instance_groups:
    - name: log-api
    ---   vm_type: minimal
    +++   vm_resources:
    +++     cpu: 2
    +++     ram: 2048
    +++     ephemeral_disk_size: 10240
    ```

1. Redeploy Cloud Foundry.

1. Run `bosh vms` to check the `VM Type` of the VM. The VM type will be `-`. Then you can check the VM size in Azure Portal.

    ```
    Instance                                      Process State  AZ  IPs         VM CID      VM Type
    log-api/97d456cf-cf28-439d-b77d-25af8848fe9e  running        z1  10.0.16.18  <redacted>  -
    ```

## How to calculate the VM cloud properties

### `instance_type`

1. CPI gets all the available VM sizes in the specified region. The region is specified as the `location` in the [global configurations](https://bosh.io/docs/azure-cpi.html#global).

1. From the available VM sizes, CPI selects the possible VM sizes which have more than `vm_resources.cpu` CPUs and `vm_resources.ram` RAMs.

1. From the possible VM sizes, CPI selects the closest matched VM size.

    The `closest matched` is defined by Azure CPI. Please note VM size is determined on best effort basis. Azure CPI tries to select the VM size with the balance of cost and performance.

    CPI maintains a table of recommended VM sizes. Please check [`RECOMMENDED_VM_SIZES`](https://github.com/cloudfoundry/bosh-azure-cpi-release/blob/master/src/bosh_azure_cpi/lib/cloud/azure/instance_type_mapper.rb). The table may **CHANGE** in future.

    CPI searches each series in the table from the top to the bottom, and selects the VM sizes which are also in the list of possible VM sizes. It means these VM sizes statisfy the requirements of `vm_resources`.

    CPI selects the VM size with the minimal CPUs. If more than one VM size have the same number of CPUs, then the size with smaller memories will be selected.

    For example, if `vm_resources.cpu` is `2` and `vm_resources.ram` is `3072`, then `Standard_F2` will be the closest matched VM size.

### `ephemeral_disk`

CPI will return `N * 1024` MB as the size because Azure always uses GiB instead of MiB.

For example, if `vm_resources.ephemeral_disk_size` is `1025`, then the following size will be used.

```
'ephemeral_disk' => {
  'size' => 2048
}
```
