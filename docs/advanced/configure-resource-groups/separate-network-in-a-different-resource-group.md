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

    * [**Reference**](http://bosh.io/docs/azure-cpi.html#networks)

    For the virtual network and static public IP, Azure CPI will search them in the specified resource group. If not found, you will get an error.

    For the network security group and application security groups, Azure CPI will search them in the specified resource group. If not found, Azure CPI will search them in the default resource group. If not found in both resource groups, you will get an error.

## Sample Steps

1. [**Deploy**](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#1-prepare-azure-resources) the `bosh-setup` template in a default resource group (e.g. `RG1`).

    * You need to disable `autoDeployBosh` and `autodDeployCloudFoundry` when deploying the template, as you will need to perform additional manual steps before deploying BOSH and Cloud Foundry.

1. Create an additional resource group (e.g. `RG2`) [**manually**](https://bosh.io/docs/azure-resources.html#res-group)

    * The `location` of `RG2` should be the same as `RG1`.

1. Move the network resources (e.g. virtual network, public IPs) from `RG1` to `RG2`.

    * Refer to [**Move resources to new resource group or subscription**](https://azure.microsoft.com/en-us/documentation/articles/resource-group-move-resources/).

1. [Login the devbox](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#2-login-your-dev-box)

1. Specify the resource group name in network specs for BOSH director.

    1. Download the ops file [`use-resource-group-for-bosh-network.yml`](./use-resource-group-for-bosh-network.yml) to `~/use-resource-group-for-bosh-network.yml`.

    1. Add the lines `-o ~/use-resource-group-for-bosh-network.yml` and `-v additional_resource_group_name=RG2` to the `bosh create-env` command in `deploy_bosh.sh`.

1. Deploy your BOSH director.

    ```
    ./deploy_bosh.sh
    ```

1. Specify the resource group name in the network specs of your cloud config.

    ```yaml
    networks:
    - name: default
      type: manual
      subnets:
      - range: ((internal_cidr))
        gateway: ((internal_gw))
        azs: [z1, z2, z3]
        dns: [8.8.8.8, 168.63.129.16]
        reserved: [((internal_gw))/30]
        cloud_properties:
          resource_group_name: ((additional_resource_group_name))
          virtual_network_name: ((vnet_name))
          subnet_name: ((subnet_name))
          security_group: ((security_group))
    - name: vip
      type: vip
    ```

    Add the line `-v additional_resource_group_name=RG2` to the `bosh -n update-cloud-config` command in `deploy_cloud_foundry.sh`.

1. Deploy your Cloud Foundry.

    ```
    ./deploy_cloud_foundry.sh
    ```

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
