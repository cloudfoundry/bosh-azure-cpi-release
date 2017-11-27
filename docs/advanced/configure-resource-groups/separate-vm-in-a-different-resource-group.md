# Separate VM in A Different Resource Group

## Why Separating VM Resources

* Allow resources in CF deployment to scale out of the [quota limit](https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#resource-group-limits) of a single resource group.
* Enable ops to utilize multiple resource groups to organize and manage VMs.

## How to Specify The Resource Group

Azure CPI v26+ offers the flexibility to specify a `resource_group_name` under `cloud_properties` of the [resource_pools/vm_types](https://bosh.io/docs/azure-cpi.html#resource-pools) spec. If it is set, related resources will be created in this resource group; otherwise, they will be created in `resource_group_name` specified in the global configuration.

The resources affected by this property are:

* Virtual Machine
* Network Interface Card
* Managed Disks (including OS disk, ephemeral disk, persistent disk and snapshot)
* Dynamic Public IP for the VM
* Availability Set

Steps:

1. Add a new `vm_extension` with the property `resource_group_name` into your cloud config.

    ```
    vm_extensions:
    - name: resource-group-properties
      cloud_properties:
        resource_group_name: <resource-group-name>
    ```

    The resource group can be prepared manually before deployment, or created by CPI automatically if it does not exist.

1. You can add the vm extension `resource-group-properties` into `vm_extensions` of your instance group. Then the VMs of this instance group will be put into the resource group `<resource-group-name>`.

    1. Download the ops file [`use-resource-group-for-vms.yml`](./use-resource-group-for-vms.yml) to `~/use-resource-group-for-vms.yml`.

    1. Add the line `-o ~/use-resource-group-for-vms.yml` to the `bosh -n -d cf deploy` command in `deploy_cloud_foundry.sh`.

1. Deploy your Cloud Foundry.

    ```
    ./deploy_cloud_foundry.sh
    ```

## Deployments

### New deployment

In a new deployment, vm related resources will be put into the resource group which is defined by `resource_group_name`. If not specified, they are put into the default resource group in the global configuration.

### Migration/update

If the resource group of the VM is changed, these resources will be recreated in the new resource group:

* Virtual Machine
* Network Interface Card
* Managed OS disks and ephemeral disk
* Availability Set
* Dynamic Public IP for the VM

However, persistent disk won't be recreated, so persistent disk and its snapshot will not be moved to new resource group even if resource group of VM is changed. If you want to migrate the old disk to new resource group, you need to change disk size or `cloud_properties` of the disk, then it will be recreated in the new resource group.

>**NOTE for Availability Set and Load balancer**: When the resource group of the VM is changed, CPI will try to recreated the VM and its availability set in the new resource group. But for VMs in the same availability set and load balancer backend pool, this action will fail. In this case, please do NOT change resource group of existed VMs when they are bound with availability set and load balancers.
>  + If VMs are bound to both availability set and load balancer, the resource group only can be specified when creating them. After VMs are created, the resource group cannot be changed because of the issue described above.
>  + If VMs are only bound to availability set without load balancer, the resource group can be changed after VMs are created.
