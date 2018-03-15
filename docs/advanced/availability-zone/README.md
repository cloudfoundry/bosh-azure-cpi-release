# Integrating Availability Zones with Cloud Foundry on Azure

An Azure [Availability Zone](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview) (AZ) is a physically separate zone within an Azure region. Within this document you will see how to integrate AZs with Cloud Foundry (CF) to implement high availability.

## Pre-requisites

* You need to enable managed disks in your bosh director by setting `use_managed_disks` to `true`. Please note the VMs with unmanaged disks do not support AZ.

    - To setup bosh director on Azure, please either refer to this [document](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) to prepare a CF environment via Azure ARM template, or refer to this [document](https://bosh.io/docs/init-azure.html) to prepare a bosh director using bosh CLI v2 manually.
    - To enable managed disks, please refer to this [link](../managed-disks/README.md).

* You need a valid deployment manifest.

    - You can either refer to this [ARM template](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) or [cf-deployment](https://github.com/cloudfoundry/cf-deployment) to get a CF deployment manifest.

* Before AZ General Availability (GA), you need to [sign up for the Availability Zones preview](http://aka.ms/azenroll) for your subscription. Please note that not all regions and VM sizes are supported. Read this [document](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview) to get regions and VM sizes that support AZs.

* Prepare a `Standard SKU` [public IP address](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-public-ip-address) or a `Standard SKU` [load balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview) (LB). `Basic SKU` public IP or LB does not work with AZs.

    - If you use a public IP address directly in a POC environment. You can use Azure CLI v2 to create the public IP:

        ```bash
        az network public-ip create --resource-group ${resource_group_name} --name ${standard_sku_public_ip_name} --location "${location}" --allocation-method Static --sku Standard
        ```

    - If you use an Azure load balancer. You can use following ARM template to create one LB.

        <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcloudfoundry-incubator%2Fbosh-azure-cpi-release%2Fmaster%2Fdocs%2Fadvanced%2Favailability-zone%2Ftemplates%2Fazuredeploy.json" target="_blank">
        <img src="http://azuredeploy.net/deploybutton.png"/>
        </a>

## Configure

1. Configure AZs

    - If you are using [cloud config](https://bosh.io/docs/cloud-config.html). Add `availability_zone` in `cloud_properties` for `azs`. Example:

        ```yaml
        azs:
        - name: z1
          cloud_properties:
            availability_zone: "1"
        - name: z2
          cloud_properties:
            availability_zone: "2"
        - name: z3
          cloud_properties:
            availability_zone: "3"

        networks:
        - name: default
          type: manual
          subnets:
          - range: ((internal_cidr))
            gateway: ((internal_gw))
            azs: [z1, z2, z3]
            dns: [168.63.129.16]
            reserved: [((internal_gw))/30]
        cloud_properties:
          …
        ```

    - If you still specify IaaS and IaaS agnostic configuration in a single file. Add `availability_zone` in `cloud_properties` for `resource_pools`. Example:

        ```yaml
        resource_pools:
        - cloud_properties:
            instance_type: Standard_F1
            availability_zone: "1"
          env:
            bosh:
              password: $6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0
          name: small_z1
          network: cf1
          stemcell:
            name: bosh-azure-hyperv-ubuntu-trusty-go_agent
            version: latest
        ```

1. Configure endpoint

    - If you use a public IP address directly in a POC environment

        * Use the `Standard SKU` public IP address in vip network, example:

            ```yaml
            - default_networks:
              - name: cf1
              instances: 1
              name: ha_proxy_z1
              networks:
              - name: reserved  # vip network type
                static_ips:
                - REPLACE_WITH_STANDARD_SKU_PUBLIC_IP # use the standard sku public ip
            ```
        * If you use <public_ip>.xip.io as system domain, replace this value accordingly.

    - If you use an Azure load balancer

        * Change value of `load_balancer` in `resource_pools` or `vm_extensions` to use the `Standard SKU` load balancer.
        * Remove `availability_set` if it exists.

    - If you use an Azure application gateway, no change is needed.

> Note: When a VM is in a zone, it can't be in any Availability Set. CPI will raise an error if you have both `availability_zone` and `availability_set` specified for a VM.

## Deploy!
Go ahead to deploy your cloud foundry.

## For Migration

Azure CPI supports migration from regional deployment to zonal deployment. If you add `availability_zone` to cloud_properties of VMs for an existed regional deployment and redeploy CF, CPI will migrate the VMs and data disks to corresponding zones.

1. VM will be deleted and recreated in the specified zone.
1. If the VM has a data disk attached, CPI will migrate the data disk to the specified zone when CPI attaches the data disk to it.

    CPI will take a snapshot of the data disk, delete the origian data disk, create a new data disk (reuse the disk name) from the snapshot, then delete the snapshot. Finally, CPI will attach the new data disk to the VM.

    CPI is careful enough when operating data disks. However, if you see an error during disk migration, you might need to migrate it manually to the zone accordingly (you can get zone number in bosh error log).
    * if the data disk is not removed. Since the disk name should not be changed after it is migrated, so typicall migration steps are:
      1. take a snapshot of the data disk.
      1. note down the disk name and delete the data disk.
      1. create a new data disk in the specific zone, the new disk should use the same disk name noted down in previous step.
      1. now you should be able to redeploy CF.
      1. validate your CF, and if everything is ok you can delete the snapshot.
    * if the data disk is removed, it should have a snapshot available. You need to get the snapshot and disk name from bosh error log, and follow steps c to e in previous condition to do migration.

As `Basic SKU` resources don't work with AZs, you need to use the `Standard SKU` resources to replace them before redeployment. See how to create those `Standard SKU` resources in [Pre-requisites](#pre-requisites).
1. You need to replace IP address of vip with a `Standard SKU` public IP if it is specified.
1. You need to replace load_balancer with a `Standard SKU` load balancer if it is specified.
1. You need to remove the `availability_set` if it is specified.

