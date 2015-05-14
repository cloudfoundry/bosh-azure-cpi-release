# BOSH Azure Cloud Provider Interface

## Options

These options are passed to the Azure CPI when it is instantiated.

### Azure options

* `environment` (required)
  The environment for Azure Management Service: AzureCloud or AzureChinaCloud
* `api_version` (required)
  The API version of Azure Management Service. 2015-05-01-preview
* `subscription_id` (required)
  Azure Subscription Id
* `storage_account_name` (required)
  Azure storage account name
* `storage_access_key` (required)
  Azure storage access key
* `resource_group_name` (required)
  Resource group name to use when spinning up new vms
* `tenant_id` (required)
  The tenant id for your service principal
* `client_id` (required)
  The client id for your service principal
* `client_secret` (required)
  The client secret for your service principal
* `ssh_certificate` (required)
  The content of the default certificate to use when spinning up new vms
* `ssh_private_key` (required)
  The content of the default private key to use when spinning up new vms
* `container_name` (optional)
  Contianer name in Azure storage account, defaults to 'bosh'

### Registry options

The registry options are passed to the Azure CPI by the BOSH director based on the settings in `director.yml`, but can be
overridden if needed.

* `endpoint` (required)
  registry URL
* `user` (required)
  registry user
* `password` (required)
  registry password

### Agent options

Agent options are passed to the Azure CPI by the BOSH director based on the settings in `director.yml`, but can be
overridden if needed.

### Resource pool options

These options are specified under `cloud_options` in the `resource_pools` section of a BOSH deployment manifest.

* `instance_type` (required)
  which [type of instance](https://msdn.microsoft.com/en-us/library/azure/dn197896.aspx) the VMs should belong to

### Network options

These options are specified under `cloud_options` in the `networks` section of a BOSH deployment manifest.

* `type` (required)
  can be either `dynamic` for a DHCP assigned IP by Azure, or 'manual' to use an assigned IP by BOSH director,
  or `vip` to use an Reserved IP (which needs to be already allocated)

## Example

This is a sample of how Azure specific properties are used in a BOSH deployment manifest:

    ---
    name: sample
    director_uuid: 081e60b9-160e-4236-b12f-ea11293d95e3

    ...

    networks:
      - name: reserved
        type: vip
        cloud_properties: {}
      - name: default
        type: manual
        subnets:
        - range:   10.0.0.0/20
          reserved: [10.0.0.2 - 10.0.0.6]
          cloud_properties:
            virtual_network_name: boshvnet
            subnet_name: BOSH
            tcp_endpoints:
            - "22:22"
            - "53:53"
            - "4222:4222"
            - "6868:6868"
            - "25250:25250"
            - "25555:25555"
            - "25777:25777"
            udp_endpoints:
            - "68:68"

    ...

    resource_pools:
      - name: default
        network: default
        size: 3
        stemcell:
          name: bosh-azure-hyperv-ubuntu-trusty-go_agent
          version: latest
        cloud_properties:
          instance_type: Standard_A1

    ...

    properties:
      azure:
        environment: AzureCloud
        api_version: 2015-05-01-preview
        subscription_id: <your_subscription_id>
        storage_account_name: <your_storage_account_name>
        storage_access_key: <your_storage_access_key>
        resource_group_name: <your_resource_group_name>
        tenant_id: <your_tenant_id>
        client_id: <your_client_id>
        client_secret: <your_client_secret>
        ssh_certificate: <content_of_your_ssh_certificate>
        ssh_private_key: <content_of_your_ssh_private_key>