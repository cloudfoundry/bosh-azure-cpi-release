# Deploy Cloud Foundry Mongodb Service

[cf-services-contrib-release](https://github.com/cloudfoundry-community/cf-services-contrib-release) contains a wide set of interesting services that can be added into your own Cloud Foundry. This page shows how to deploy Cloud Foundry Mongodb Service on Azure.

Please read the [README](https://github.com/cloudfoundry-community/cf-services-contrib-release/blob/master/README.md) at first. From it, you can learn how to deploy these services on Cloud Foundry.

## Prerequisites

- A deployment of [BOSH](https://github.com/cloudfoundry/bosh)
- A deployment of [Cloud Foundry](https://github.com/cloudfoundry/cf-release)
- If you have deployed Cloud Foundry on Azure following the [guidance](../../guidance.md), you are ready with both.

## Deploy

### 1 Upload the stemcell

You can use the stemcell that is already uploaded with your Cloud Foundry deployment.

### 2 Upload a BOSH release for mongodb service

Below are sample commands to upload a BOSH release for Mongodb, using V6 as an example. You can check https://github.com/cloudfoundry-community/cf-services-contrib-release/releases to identify the latest stable build, note some configurations might change with new versions.

```
bosh upload release https://cf-contrib.s3.amazonaws.com/boshrelease-cf-services-contrib-6.tgz
```

### 3 Create infrastructure

Prior to deployment, you should define a new subnet `mongodb` where the Mongodb service is deployed. You need to update the subnet configuration in the manifest of Step #4.

You can create subnets using Azure Portal, Azure CLI or Azure Powershell. Here is the sample in Azure CLI.

```
azure network vnet subnet create --resource-group <resource-group-name> --vnet-name <virtual-network-name> --name <subnet-name> --address-prefix <subnet-cidr>
```

For example:

```
azure network vnet subnet create --resource-group "myResourceGroup" --vnet-name "vnet" --name "mongodb" --address-prefix "10.0.64.0/24"
```

<a name="create-manifest"/>
### 4 Create the manifest

We provide a sample manifest [**cf-mongodb-azure-sample.yml**](./cf-mongodb-azure-sample.yml). You need to rename `cf-mongodb-azure-sample.yml` into `cf-mongodb-azure.yml` and update the following values.

* `REPLACE_WITH_DIRECTOR_ID`

  Run `bosh status --uuid` to get the director ID.

* `networks` section

  Update the network according to the subnet you created in Step #3.

* `REPLACE_WITH_STEMCELL_VERSION`

  You can get the stemcell name and version using `bosh stemcells`.

  Sample Output:

  ```
  Acting as user 'admin' on 'bosh'

  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | Name                                     | OS            | Version | CID                                                |
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | bosh-azure-hyperv-ubuntu-trusty-go_agent | ubuntu-trusty | 0000*   | bosh-stemcell-bd80bc85-994d-4271-b2c3-12e530a72a44 |
  +------------------------------------------+---------------+---------+----------------------------------------------------+

  (*) Currently in-use

  Stemcells total: 1
  ```

* `REPLACE_WITH_YOUR_CF_SYSTEM_DOMAIN` and `REPLACE_WITH_NATS_ADDRESS`

  You should use the values which are defined in your manifest for Cloud Foundry deployment.

* `MONGODB_SERVICE_TOKEN`

  You need to make up a token which you will use later with `cf create-service-auth-token`.

### 5 Deploy

```
bosh deployment cf-mongodb-azure.yml
bosh -n deploy
```

After the deployment, you'll get 2 VMs for Mongodb service.

```
+------------------------+---------+---------------+-----------+
| Job/index              | State   | Resource Pool | IPs       |
+------------------------+---------+---------------+-----------+
| gateways/0             | running | common        | 10.0.64.6 |
| mongodb_service_node/0 | running | common        | 10.0.64.7 |
+------------------------+---------+---------------+-----------+

VMs total: 2
```

By default, the instance type of the VMs is `Standard_D1` which means you'll need 2 cores for Mongodb service. **If you do not have so many cores in your subscription, you need to upgrade your subscription.**

### 6 Create a mongodb service

Finally, you need to authorize mongodb service gateway with your Cloud Foundry.

1. First register the broker using the `cf` CLI.

  You must be logged in as an admin.
  
  ```
  cf login -a https://api.<system-domain> --skip-ssl-validation # Username: admin; Password: c1oudc0w
  ```
  
  You should create the organization and space if you login Cloud Foundry for the first time.
  
  For more information, see [Getting Started with the cf CLI](http://docs.cloudfoundry.org/devguide/installcf/whats-new-v6.html#login).

2. Security Groups

  Since [cf-release](https://github.com/cloudfoundry/cf-release) v175, applications by default cannot to connect to IP addresses on the private network. This prevents applications from connecting to the Mongodb service.
  
  Add the rule to a file in the following json format; multiple rules are supported.

  ```
  [
    {
      "destination": "10.0.64.6-10.0.64.7",
      "protocol": "all"
    }
  ]
  ```

  - Create a security group from the rule file.
    ```shell
    $ cf create-security-group mongodb rule.json
    ```
  
  - Enable the rule for all apps
    ```
    $ cf bind-running-security-group mongodb
    ```
  
  Security group changes are only applied to new application containers; existing apps must be restarted.

3. Create a service

  ```
  $ cf create-service-auth-token <label> core <token>
  ```
  
  - **label**: the name of the package
  - **token**: the token you provided in your deployment file
  
  For example:
  
  ```
  $ cf create-service-auth-token mongodb core mytoken
  ```
  
  You and all your users can now provision and bind the services:
  
  ```
  $ cf create-service mongodb default my-mongodb
  Creating service my-mongodb in org <org> / space <space> as <user>...
  OK
  ```

Then you can use mongodb service in your APP.

## Appendix

### How to generate a sample manifest for Azure

This section demonstrates how to generate an Azure manifest file for `cf-services-contrib-release`. [cf-services-contrib-release](https://github.com/cloudfoundry-community/cf-services-contrib-release) contains multiple service brokers, it comes with a generic manifest file [dns-all.yml](./dns-all.yml), you can generate an Azure manifest for a specific service (like MongoDB) following below steps. The following steps can be a reference if you want to modify other deployment manifest, for example a manifest for deploying Cloud Foundry Redis service on Azure. **If you don't want to modify the manifest for other services, please skip this section.**

1. Update the deployment name.

  Before Step 1:

  ```
  name: cf-services-contrib
  director_uuid: DIRECTOR_UUID   # CHANGE
  ---
  
  releases:
  ```

  After Step 1:

  ```
  ---
  name: cf-mongodb-azure
  director_uuid: REPLACE_WITH_DIRECTOR_ID

  releases:
  ```

  >**NOTE:** `---` should be put at the beginning of the manifest.

2. Update the version of the release.

  If the release you uploaded is version 6, you should update the version to 6.

  ```
  releases:
  - name: cf-services-contrib
    version: 6
  ```

3. Update the `instance_type`.

  Update it into the instance type for Azure.

  For example:

  ```
  instance_type: Standard_D1
  ```

4. Update the `networks`.

  ```
  networks:
    - name: default
      type: manual
      subnets: # Update the subnet
      - range: 10.0.64.0/24
        gateway: 10.0.64.1
        dns: [10.0.0.100]
        reserved: ["10.0.64.2 - 10.0.64.3"]
        cloud_properties:
          virtual_network_name: REPLACE_WITH_VIRTUAL_NETWORK_NAME
          subnet_name: REPLACE_WITH_SUBNET_NAME_FOR_MONGODB
  ```

5. Remove other services.

  1. Remove other service nodes in `jobs`.
  2. Remove other service plans in `service_plans`.
  3. Remove other gateway properties.

6. Update the `stemcell`.

  ```
  resource_pools:
    - name: common
      network: default
      size: 2
      stemcell:
        name: bosh-azure-hyperv-ubuntu-trusty-go_agent
        version: REPLACE_WITH_STEMCELL_VERSION
      cloud_properties:
        instance_type: Standard_D1
  ```

  The size should be reduced into `2` because the other services have been removed.

7. Update the endpoint.

  Change `mycloud.com` into `REPLACE_WITH_YOUR_CF_SYSTEM_DOMAIN`.

8. Update the configuration based on your Cloud Foundry manifest

  The following configurations should be same as the configurations in your manifest for Cloud Foundry.

  * `nats`

    ```
    nats:
      address: REPLACE_WITH_NATS_ADDRESS # e.g. 10.0.16.4
      port: 4222
      user: nats
      password: c1oudc0w
      authorization_timeout: 5
    ```

  * `uaa`

    ```
    uaa_client_auth_credentials:
      username: admin
      password: c1oudc0w
    ```
