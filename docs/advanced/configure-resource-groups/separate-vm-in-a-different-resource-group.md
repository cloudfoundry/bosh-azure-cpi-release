# Separate VM in A Different Resource Group

## Why Separating VM Resources

  1. Allow resources in CF deployment to scale out of the [quota limit](https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#resource-group-limits) of a single resource group.
  1. Enable ops to utilize multiple resource groups to organize and manage VMs.

## How to Specify The Resource Group

Azure CPI V26+ offers the flexibility to specify a `resource_group_name` under `cloud_properties` of the [resource_pools/vm_types](https://bosh.io/docs/azure-cpi.html#resource-pools) spec. If it is set, related resources will be created in this resource group; otherwise, they will be created in `resource_group_name` specified in the global CPI settings (`bosh.yml`). The resources affected by this property are:
  1. Virtual Machine
  1. Network Interface Card
  1. Managed Disks (including OS disk, ephemeral disk, persistent disk and snapshot)
  1. Dynamic Public IP for the VM
  1. Availability Set

Example of resource_pools:

  ```yaml
  resource_pools:
  - cloud_properties:
      instance_type: Standard_F1
      resource_group_name: RG1
    env:
      bosh:
        password: $6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0
    name: small_z1
    network: cf1
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
  ```

The resource group can be prepared manually before deployment, or created by CPI automatically if it does not exist.

## Deployments

###	New deployment

In a new deployment, related resources will be put in the resource group defined in its resource_pools or in default resource group if `resource_group_name` is not specified.

###	Migration/update

If the resource group of the VM is changed, these resources will be recreated in the new resource group:
  1. Virtual Machine
  1. Network Interface Card
  1. managed OS disks and ephemeral disk
  1. Availability Set
  1. Dynamic Public IP for the VM

However, persistent disk won't be recreated, so persistent disk and its snapshot will not be moved to new resource group even if resource group of VM is changed. If you want to migrate the old disk to new resource group, you need to change disk size or cloud_properties of the disk, then it will be recreated in the new resource group.

>**NOTE for Availability Set and Load balancer**: When the resource group of the VM is changed, CPI will try to recreated the VM and its availability set in the new resource group. But for VMs in the same availability set and load balancer backend pool, this action will fail. In this case, please do NOT change resource group of existed VMs when they are bound with availability set and load balancers.
>  + If VMs are bound to both availability set and load balancer, the resource group only can be specified when creating them. After VMs are created, the resource group cannot be changed because of the issue described above.
>  + If VMs are only bound to availability set without load balancer, the resource group can be changed after VMs are created.
