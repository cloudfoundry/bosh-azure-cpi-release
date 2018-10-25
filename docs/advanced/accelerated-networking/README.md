# Use Azure Accelerated Networking

[Accelerated networking (AN)](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli) enables single root I/O virtualization (SR-IOV) to a VM, greatly improving its networking performance. This high-performance path bypasses the host from the datapath, reducing latency, jitter, and CPU utilization, for use with the most demanding network workloads on supported VM types. 

## Cloud Foundry

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

## Pivotal Cloud Foundry

### Requirements

* [PCF Ops manager v2.3.1+](https://docs.pivotal.io/pivotalcf/2-3/pcf-release-notes/opsmanager-rn.html#2-3-1) is required, where `Azure CPI v35.4.0` and stemcell 97.18 (Xenial) is installed.

* [PCF Ops manager CLI `om`](https://github.com/pivotal-cf/om) is required. The [Pivotal doc](https://docs.pivotal.io/pivotalcf/2-3/customizing/custom-vm-extensions.html) uses `curl` with `UAA_ACCESS_TOKEN` to manage custom VM extensions. In this doc, `om` is used for simplicity.

* You need to review the supported VM instances and regions in [Limitations and Constraints](https://docs.microsoft.com/en-us/azure/virtual-network/create-vm-accelerated-networking-cli#limitations-and-constraints) before you continue.

### Steps

1. Configure the credentials of Ops manager as environment variables.

    ```
    export OM_TARGET=<OPS-MANAGER-URL>
    export OM_USERNAME=<USERNAME>
    export OM_PASSWORD=<PASSWORD>
    ```

1. Create a VM extension with accelerated networking enabled.


    ```
    om -k create-vm-extension --config config.yml
    ```

    The contents of `config.yml`:

    ```
    vm-extension-config:
      name: enable_accelerated_networking
      cloud_properties:
        accelerated_networking: true
    ```

1. Get the current resource config of the instance group which you want to enable accelerated networking.

    ```
    PRODUCT_GUID=$(om -k curl \
      --path "/api/v0/deployed/products" \
      --request "GET" \
      | jq -r '.[] | select(.type=="cf") | .guid')

    JOB_GUID=$(om -k curl \
      --path "/api/v0/staged/products/${PRODUCT_GUID}/jobs" \
      --request "GET" \
      | jq -r '.jobs | .[] | select(."name" == "diego_cell") | .guid')

    om -k curl \
      --path "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${JOB_GUID}/resource_config" \
      --request "GET"
    ```

    The output would be like:

    ```
    {
      "instance_type": {
        "id": "automatic"
      },
      "instances": 3,
      "internet_connected": false,
      "elb_names": [],
      "additional_vm_extensions": [],
      "swap_as_percent_of_memory_size": "automatic"
    }
    ```

1. Update the resource config to use the extension `enable_accelerated_networking`, and apply changes.

    ```
    om -k curl \
      --path "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${JOB_GUID}/resource_config" \
      --request "PUT" \
      --data '{
                "instance_type": {
                  "id": "automatic"
                },
                "instances": 3,
                "internet_connected": false,
                "elb_names": [],
                "additional_vm_extensions": ["enable_accelerated_networking"],
                "swap_as_percent_of_memory_size": "automatic"
              }'
    
    om -k apply-changes \
      --ignore-warnings \
      --product-name "cf"
    ```

## Known Issues

1. Existing availability set was not deployed on accelerated networking enabled cluster.

    ```
    Error message: {
      "error": {
        "details": [],
        "code": "ExistingAvailabilitySetWasNotDeployedOnAcceleratedNetworkingEnabledCluster",
        "message": "Cannot add Virtual Machine with accelerated networking-enabled nics (/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Compute/virtualMachines/<vm-name>) on an existing non-accelerated networking AvailabilitySet (/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Compute/availabilitySets/<availability-set-name>)."
      }
    }>
    ```

     You need to create a [VM Extension](http://bosh.io/docs/azure-cpi/#resource-pools) with a new availability set name. Azure CPI will create the availability set with accelerated networking enabled. However, there's a requirement: the SKU of your load balancer has to be `Standard`. If not, you can follow the [doc](../migrate-basic-lb-to-standard-lb/) to migrate basic load balancer to standard load balancer.
