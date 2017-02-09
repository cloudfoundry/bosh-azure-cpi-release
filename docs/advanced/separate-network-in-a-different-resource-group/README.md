# Separate Network in A Different Resource Group

## Why Separating Network Resources

For system stability and security, some organization may need to manage the network resources (Virtual Network, Network Security Group and Public IP) separately. For this purpose, Azure CPI V13 and above supports grouping network resources under an additional resource group.

## How to Specify The Resource Group

Azure CPI V13 offers the flexibility to specify a resource group name under `cloud_properties` of the network spec. If it is specified, Azure CPI will search the virtual network, security groups and public IPs in this resource group. Otherwise, Azure CPI will search them in `resource_group_name` in the global CPI settings (`bosh.yml`).

* Virtual Network

  The `resource_group_name` for Virtual Network is specified in the `dynamic/manual` network specs.

  For example:

  ```
  networks:
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

  If `resource_group_name` is specified, Azure CPI will search the virtual network in it. If the virtual network is not found, you will get an error.

* Network Security Group

  The `resource_group_name` for Network Security Group is specified in the `dynamic/manual` network specs.

  For example:

  ```
  networks:
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
        security_group: nsg-bosh
  ```

  If `resource_group_name` is specified, Azure CPI will search the security group in it. If the security group is not found in the specified resource group, Azure CPI will search the security group in the default resource group (`resource_group_name` in `bosh.yml`). If the security group is not found in both resource group, you will get an error.

* Public IP

  The `resource_group_name` for Public IP is specified in the `vip` network specs.

  For example:

  ```
  networks:
  - name: public
    type: vip
    cloud_properties:
      resource_group_name: RG2
  ```

  The public IP is specified in the section `jobs.networks`.

  ```
  jobs:
  - name: YOUR_JOB_NAME
    networks:
    - name: public
      static_ips: REPLACE_WITH_PUBLIC_IP_ADDRESS
  ```

  If `resource_group_name` is specified, Azure CPI will search the public IP in it. If the public IP is not found, you will get an error.

## Sample Steps

Before you perform the following steps, you need to understand the basic steps of [deploying BOSH and Cloud Foundry](../../../docs#22-deploy-bosh-and-cloud-foundry).

### Using bosh-setup template

1. [**Deploy**](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#1-prepare-azure-resources) the `bosh-setup` template in a default resource group (e.g. `RG1`).

  * You need to disable `autoDeployBosh` when deploying the template, as you will need to perform additional manual steps before deploying BOSH.

2. Create an additional resource group (e.g. `RG2`) [**manually**](https://bosh.io/docs/azure-resources.html#res-group)

  * The `location` of `RG2` should be the same as `RG1`.

3. Move the virtual network, network security groups and public IPs from `RG1` to `RG2`.

  * Refer to [**Move resources to new resource group or subscription**](https://azure.microsoft.com/en-us/documentation/articles/resource-group-move-resources/).

4. [Login the devbox](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#2-login-your-dev-box)

5. Specify the resource group name in `bosh.yml`.

  ```
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

6. [Deploy BOSH](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md#3-deploy-bosh)

7. Specify the resource group name in the manifest of Cloud Foundry.

  ```
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

8. [Deploy Cloud Foundry](../../get-started/via-arm-templates/deploy-cloudfoundry-via-arm-templates.md)

### Manually

You can refer to [the manual steps](https://bosh.io/docs/azure-resources.html) for how to prepare the resource groups.

1. [Create two resource groups](https://bosh.io/docs/azure-resources.html#res-group) (e.g. `RG1` and `RG2`).

2. [Create a public IP for Cloud Foundry](https://bosh.io/docs/azure-resources.html#public-ips) in `RG2`.

3. [Create a Virtual Network](https://bosh.io/docs/azure-resources.html#virtual-network) in `RG2`.

4. [Setup a default Storage Account](https://bosh.io/docs/azure-resources.html#storage-account) in `RG1`.

  When you create a network interface using a subnet from a different resource group, the command is a little different. You should use `--subnet-id` instead of `--subnet-name` in `azure network nic create`. Similarly, you should use `--subnet-id` in `azure vm create` too.

5. Update the manifest for BOSH, specify the resource group name and [deploy BOSH](https://bosh.io/docs/init-azure.html#deploy).

  ```
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

7. Update the manifest for Cloud Foundry, specify the resource group name and [deploy Cloud Foundry](https://docs.cloudfoundry.org/deploying/common/deploy.html#deploy).

  ```
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

 | Resource Group for VMs | Resource Group for Network
------------ | ------------ | -------------
Service Principal for CF Admin Team | Owner | Reader
Service Principal for Network Team | Reader | Owner

That is to say, CF Admin Team can manage everything including access in the resource group for VMs, and view everything, but can't make changes in the resource group for network.

```
azure role assignment create --spn <service-principal-name-for-cf-admin-team> --roleName "Owner" --resource-group <resource-group-name-for-vms>
azure role assignment create --spn <service-principal-name-for-cf-admin-team> --roleName "Reader" --resource-group <resource-group-name-for-network>

azure role assignment create --spn <service-principal-name-for-network-team> --roleName "Reader" --resource-group <resource-group-name-for-vms>
azure role assignment create --spn <service-principal-name-for-network-team> --roleName "Owner" --resource-group <resource-group-name-for-network>
```

You can refer to [RBAC: Built-in roles](https://azure.microsoft.com/en-us/documentation/articles/role-based-access-built-in-roles/) to assign different roles according to your own needs.
