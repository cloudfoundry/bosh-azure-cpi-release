# Use Azure Accelerated Networking

[Accelerated networking (AN)](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli) enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. This high-performance path bypasses the host from the datapath, reducing latency, jitter, and CPU utilization, for use with the most demanding network workloads on supported VM types. 

## Requirements

* Azure CPI v35.4.0+ is required.

* You need to review the supported VM instances and regions in [Limitations and Constraints](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#limitations-and-constraints) before you continue.

* The stemcell [ubuntu-xenial v81+](http://bosh.io/stemcells/bosh-azure-hyperv-ubuntu-xenial-go_agent) is required because AN needs [Ubuntu 16.04](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#supported-operating-systems) and [linux-generic-hwe-16.04-edge 4.15.0.23.45](https://github.com/cloudfoundry/bosh-linux-stemcell-builder/issues/47).

## Steps

1. Upload your stemcell [ubuntu-xenial v81+](http://bosh.io/stemcells/bosh-azure-hyperv-ubuntu-xenial-go_agent).

1. Select supported VM size according to [Limitations and Constraints](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#limitations-and-constraints). Otherwise, you will hit the error `VMSizeIsNotPermittedToEnableAcceleratedNetworking`.

1. In your cloud config, set `accelerated_networking: true` in [network configuration](http://bosh.io/docs/azure-cpi/#dynamic-network-or-manual-network) or [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). Then, run `bosh update-cloud-config`.

1. Use the xenial stemcell to deploy Cloud Foundry.

    You can refer to the [ops file](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/experimental/use-xenial-stemcell.yml) and update it with your stemcell version.

    ```
    bosh -d cf deploy cf-deployment.yml \
    ...
    -o use-xenial-stemcell.yml \
    ...
    ```

    * For a new deployment, all the VMs are newly created using the ubuntu-xenial stemcell.

    * For an existing deployment, all the VMs are re-created and updated because a new stemcell is used.

        If you hits the following error, you need to check the SKU of your load balancer.

            ```
            Error message: {
              "error": {
                "details": [],
                "code": "ExistingAvailabilitySetWasNotDeployedOnAcceleratedNetworkingEnabledCluster",
                "message": "Cannot add Virtual Machine with accelerated networking-enabled nics (/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Compute/virtualMachines/<vm-name>) on an existing non-accelerated networking AvailabilitySet (/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Compute/availabilitySets/<availability-set-name>)."
              }
            }>
            ```

        * If the load balancer SKU is `Standard`, you can fix the error by changing the availability set name to a new one in your [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools).

        * If the load balancer SKU is `Basic`, you have to delete the failed VMs and its availability set, and recreate them. There's downtime in this progress.
