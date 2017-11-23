# Separate Network in A Different Resource Group

## Why Separating Network Resources

For system stability and security, some organization may need to manage the network resources separately in an additional resource group.

Azure CPI v13+ supports grouping the following network resources under an additional resource group:

* Virtual Network
* Network Security Group
* Static Public IP

Azure CPI v31+ supports grouping the following network resources under an additional resource group:

* Application Security Groups

## How to Specify The Resource Group

Azure CPI offers the flexibility to specify a resource group name under `cloud_properties` of the network spec. If it is specified, Azure CPI will search the network resources in this resource group. Otherwise, Azure CPI will search them in the default resource group specified in the global configuration.

* `resource_group_name` specified in the network specs.

    ```yaml
    networks:
    - name: default
      type: manual
      subnets:
      - range: 10.0.0.0/24
        gateway: 10.0.0.1
        dns: [168.63.129.16]
        cloud_properties:
          resource_group_name: RG2
          virtual_network_name: boshvnet-crp
          subnet_name: Bosh
          security_group: nsg-bosh
    - name: vip
      type: vip
      cloud_properties:
        resource_group_name: RG2
    ```

    For the virtual network and static public IP, Azure CPI will search them in the specified resource group. If not found, you will get an error.

    For the network security group and application security groups, Azure CPI will search them in the specified resource group. If not found, Azure CPI will search them in the default resource group. If not found in both resource groups, you will get an error.

## Sample Steps

Before you perform the following steps, you need to understand the basic steps of [deploying BOSH and Cloud Foundry](../../../docs#22-deploy-bosh-and-cloud-foundry).

### Using bosh-setup template

1. [**Deploy**](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#1-prepare-azure-resources) the `bosh-setup` template in a default resource group (e.g. `RG1`).

    * You need to disable `autoDeployBosh` when deploying the template, as you will need to perform additional manual steps before deploying BOSH.

1. Create an additional resource group (e.g. `RG2`) [**manually**](https://bosh.io/docs/azure-resources.html#res-group)

    * The `location` of `RG2` should be the same as `RG1`.

1. Move the virtual network, network security groups and public IPs from `RG1` to `RG2`.

    * Refer to [**Move resources to new resource group or subscription**](https://azure.microsoft.com/en-us/documentation/articles/resource-group-move-resources/).

1. [Login the devbox](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#2-login-your-dev-box)

1. Specify the resource group name in `bosh.yml`.

    ```yaml
    networks:
    - name: public
      type: vip
      cloud_properties:
        resource_group_name: RG2
    - name: private
      type: manual
      subnets:
      - range: 10.0.0.0/24
        gateway: 10.0.0.1
        dns: [168.63.129.16]
        cloud_properties:
          resource_group_name: RG2
          virtual_network_name: boshvnet-crp
          subnet_name: Bosh
    ```

    * [**Reference**](http://bosh.io/docs/azure-cpi.html#networks)

1. [Deploy BOSH](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#3-deploy-bosh)

1. Specify the resource group name in the manifest of Cloud Foundry.

    ```yaml
    networks:
    - name: cf_private
      type: manual
      subnets:
      - range: 10.0.16.0/20
        gateway: 10.0.16.1
        dns: [168.63.129.16]
        reserved: ["10.0.16.2 - 10.0.16.3"]
        static: ["10.0.16.4 - 10.0.16.100"]
        cloud_properties:
          resource_group_name: RG2
          virtual_network_name: boshvnet-crp
          subnet_name: CloudFoundry
    - name: cf_public
      type: vip
      cloud_properties:
        resource_group_name: RG2
    ```

    * [**Reference**](http://bosh.io/docs/azure-cpi.html#networks)

1. [Deploy Cloud Foundry](../../get-started/via-arm-templates/deploy-cloudfoundry-via-arm-templates.md)

### Manually

You can refer to [the manual steps](https://bosh.io/docs/azure-resources.html) for how to prepare the resource groups.

1. [Create two resource groups](https://bosh.io/docs/azure-resources.html#res-group) (e.g. `RG1` and `RG2`).

1. [Create a public IP for Cloud Foundry](https://bosh.io/docs/azure-resources.html#public-ips) in `RG2`.

1. [Create a Virtual Network](https://bosh.io/docs/azure-resources.html#virtual-network) in `RG2`.

1. [Setup a default Storage Account](https://bosh.io/docs/azure-resources.html#storage-account) in `RG1`.

    When you create a network interface using a subnet from a different resource group, the command is a little different. You should use `--subnet-id` instead of `--subnet-name` in `az network nic create`. Similarly, you should use `--subnet-id` in `azure vm create` too.

1. Update the manifest for BOSH, specify the resource group name and [deploy BOSH](https://bosh.io/docs/init-azure.html#deploy).

    ```yaml
    networks:
    - name: public
      type: vip
      cloud_properties:
        resource_group_name: RG2
    - name: private
      type: manual
      subnets:
      - range: 10.0.0.0/24
        gateway: 10.0.0.1
        dns: [168.63.129.16]
        cloud_properties:
          resource_group_name: RG2
          virtual_network_name: boshvnet-crp
          subnet_name: Bosh
    ```

    * [**Reference**](http://bosh.io/docs/azure-cpi.html#networks)

1. Update the manifest for Cloud Foundry, specify the resource group name and [deploy Cloud Foundry](https://docs.cloudfoundry.org/deploying/common/deploy.html#deploy).

    ```yaml
    networks:
    - name: cf_private
      type: manual
      subnets:
      - range: 10.0.16.0/20
        gateway: 10.0.16.1
        dns: [168.63.129.16]
        reserved: ["10.0.16.2 - 10.0.16.3"]
        static: ["10.0.16.4 - 10.0.16.100"]
        cloud_properties:
          resource_group_name: RG2
          virtual_network_name: boshvnet-crp
          subnet_name: CloudFoundry
    - name: cf_public
      type: vip
      cloud_properties:
        resource_group_name: RG2
    ```

    * [**Reference**](http://bosh.io/docs/azure-cpi.html#networks)

## How to Assign The Service Principal Roles for The Separated Resource Groups

For system stability and security, you can create multiple service principals, and assign different roles for different resource groups.

Here is an example:

|                                     | Resource Group for VMs | Resource Group for Network |
| ----------------------------------- | ---------------------- | -------------------------- |
|Service Principal for CF Admin Team  | Owner                  | Reader                     |
|Service Principal for Network Team   | Reader                 | Owner                      |

That is to say, CF Admin Team can manage everything including access in the resource group for VMs, and view everything, but can't make changes in the resource group for network.

```
az role assignment create --assignee <service-principal-name-for-cf-admin-team> --role "Owner" --resource-group <resource-group-name-for-vms>
az role assignment create --assignee <service-principal-name-for-cf-admin-team> --role "Reader" --resource-group <resource-group-name-for-network>

az role assignment create --assignee <service-principal-name-for-network-team> --role "Reader" --resource-group <resource-group-name-for-vms>
az role assignment create --assignee <service-principal-name-for-network-team> --role "Owner" --resource-group <resource-group-name-for-network>
```

You can refer to [RBAC: Built-in roles](https://azure.microsoft.com/en-us/documentation/articles/role-based-access-built-in-roles/) to assign different roles according to your own needs.
