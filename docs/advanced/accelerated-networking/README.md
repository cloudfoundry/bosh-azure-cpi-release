# Use Azure Accelerated Networking

[Accelerated networking (AN)](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli) enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. This high-performance path bypasses the host from the datapath, reducing latency, jitter, and CPU utilization, for use with the most demanding network workloads on supported VM types.

### Requirements

* Azure CPI v35.4.0+ is required.

* The stemcell [ubuntu-xenial v81+](http://bosh.io/stemcells/bosh-azure-hyperv-ubuntu-xenial-go_agent) is required because AN needs [Ubuntu 16.04](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#supported-operating-systems) and [linux-generic-hwe-16.04-edge 4.15.0.23.45](https://github.com/cloudfoundry/bosh-linux-stemcell-builder/issues/47).

* You need to review the supported VM instances and regions in [Limitations and Constraints](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#limitations-and-constraints) before you continue.

### Steps

1. Select supported VM size according to [Limitations and Constraints](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#limitations-and-constraints). Otherwise, you will hit the error `VMSizeIsNotPermittedToEnableAcceleratedNetworking`.

1. Upload your stemcell [ubuntu-xenial v81+](http://bosh.io/stemcells/bosh-azure-hyperv-ubuntu-xenial-go_agent).

1. In your cloud config, set `accelerated_networking: true` in [network configuration](http://bosh.io/docs/azure-cpi/#dynamic-network-or-manual-network) or [VM Types/VM Extensions](http://bosh.io/docs/azure-cpi/#resource-pools). Then, run `bosh update-cloud-config`.

1. Deploy Cloud Foundry.

    ```
    bosh -d cf deploy cf-deployment.yml \
    ...
    ```

