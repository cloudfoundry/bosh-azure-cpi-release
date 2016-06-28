# Cloud Foundry MySQL Service on Azure

This page will show how to deploy Cloud Foundry MySQL Service on Azure via Bosh. You can click [**HERE**](https://github.com/cloudfoundry/cf-mysql-release/tree/master) for more informations.

### Table of contents

[Components](#components)

[Deploying](#deploying)

[Registering the Service Broker](#registering-broker)

[Security Groups](#security-groups)

[Push an APP using MySQL Service](#push-app)

[Deregistering the Service Broker](#deregistering-broker)

<a name='components'></a>
## Components

A BOSH release of a MySQL database-as-a-service for Cloud Foundry using [MariaDB Galera Cluster](https://mariadb.com/kb/en/mariadb/documentation/replication-cluster-multi-master/galera/what-is-mariadb-galera-cluster/) and a [v2 Service Broker](http://docs.cloudfoundry.org/services/).

<table>
  <tr>
      <th>Component</th><th>Description</th>
  </tr>
  <tr>
    <td><a href="https://github.com/cloudfoundry/cf-mysql-broker">CF MySQL Broker</a></td>
    <td>Advertises the MySQL service and plans.  Creates and deletes MySQL databases and
    credentials (bindings) at the request of Cloud Foundry's Cloud Controller.
    </td>
   </tr>
   <tr>
     <td>MySQL Server</td>
     <td>MariaDB 10.0.17; database instances are hosted on the servers.</td>
   </tr>
      <tr>
     <td>Proxy</td>
     <td><a href="https://github.com/cloudfoundry-incubator/switchboard">Switchboard</a>; proxies to MySQL, severing connections on MySQL node failure.</td>
   </tr>
</table>

<a name='deploying'></a>
## Deploying

### Prerequisites

- A deployment of [BOSH](https://github.com/cloudfoundry/bosh)
- A deployment of [Cloud Foundry](https://github.com/cloudfoundry/cf-release)
- If you have deployed Cloud Foundry on Azure following the [guidance](../../guidance.md), you are ready with both.

### Overview

1. [Upload Stemcell](#upload_stemcell)
1. [Upload Release](#upload_release)
1. [Create Infrastructure](#create_infrastructure)
1. [Deployment Components](#deployment_components)
1. [Create Manifest and Deploy](#create_manifest)

After installation, the MySQL service will be visible in the Services Marketplace; using the [CLI](https://github.com/cloudfoundry/cli), run `cf marketplace`.

<a name="upload_stemcell"></a>
### Upload Stemcell

You can use the stemcell that is already uploaded with your Cloud Foundry deployment.

<a name="upload_release"></a>
### Upload Release

Below are sample commands to upload a BOSH release for MySQL, using V25 as an example. You can check https://github.com/cloudfoundry/cf-mysql-release/releases to identify the latest stable build, note some configurations might change with new versions.

```
git clone https://github.com/cloudfoundry/cf-mysql-release
cd cf-mysql-release
git checkout v25
./update
bosh upload release releases/cf-mysql-25.yml
```

<a name="create_infrastructure"></a>
### Create Infrastructure

Prior to deployment, you should define three subnets. The MySQL release is designed to be deployed across three subnets to ensure availability in the event of a subnet failure. During installation, a fourth subnet is required for compilation vms. The [sample_azure_stub.yml](./sample_azure_stub.yml) demonstrates how these subnets can be configured on Azure.

You can adjust the level of availability by modifying the subnet numbers, however you need to update the manifest file later to reflect the changes.

You can create subnets using Azure Portal, Azure CLI or Azure Powershell. Here is the sample in Azure CLI.

```
azure network vnet subnet create --resource-group $resource-group-name --vnet-name $virtual-network-name --name $subnet-name --address-prefix $subnet-cidr
```

For example:

```
azure network vnet subnet create --resource-group "myResourceGroup" --vnet-name "boshvnet-crp" --name "mysql1" --address-prefix "10.0.50.0/24"
azure network vnet subnet create --resource-group "myResourceGroup" --vnet-name "boshvnet-crp" --name "mysql2" --address-prefix "10.0.51.0/24"
azure network vnet subnet create --resource-group "myResourceGroup" --vnet-name "boshvnet-crp" --name "mysql3" --address-prefix "10.0.52.0/24"
azure network vnet subnet create --resource-group "myResourceGroup" --vnet-name "boshvnet-crp" --name "compilation" --address-prefix "10.0.53.0/24"
```

<a name="deployment_components"></a>
### Deployment Components

This section descripts the components that will be created/configured after the deployment. The total number of VMs is 7. Considering the different instance type, you'll need `10(2*3+1*4)` cores. **If you do not have so many cores in your subscription, you need to consider to use smaller VM type but not use Standard\_D2.**

```
+----------------------+---------+--------------------+-----------+
| VM                   | State   | VM Type            | IPs       |
+----------------------+---------+--------------------+-----------+
| cf-mysql-broker_z1/0 | running | cf-mysql-broker_z1 | 10.0.50.9 |
| cf-mysql-broker_z2/0 | running | cf-mysql-broker_z2 | 10.0.51.9 |
| mysql_z1/0           | running | mysql_z1           | 10.0.50.4 |
| mysql_z2/0           | running | mysql_z2           | 10.0.51.4 |
| mysql_z3/0           | running | mysql_z3           | 10.0.52.4 |
| proxy_z1/0           | running | proxy_z1           | 10.0.50.5 |
| proxy_z2/0           | running | proxy_z2           | 10.0.51.5 |
+----------------------+---------+--------------------+-----------+
```

#### Database nodes

There are three mysql jobs (mysql\_z1, mysql\_z2, mysql\_z3) which should be deployed with one instance each.
Each of these instances will reside in separate subnets as described in the previous section.
The number of mysql nodes should always be odd, with a minimum count of three, to avoid [split-brain](http://en.wikipedia.org/wiki/Split-brain\_\(computing\)).
When the failed node comes back online, it will automatically rejoin the cluster and sync data from one of the healthy nodes. Note: Due to our bootstrapping procedure, if you are bringing up a cluster for the first time, there must be a database node in the first subnet.

#### Proxy nodes

There are two proxy jobs (proxy\_z1, proxy\_z2), which should be deployed with one instance each to different subnets.
The second proxy is intended to be used in a failover capacity. In the event the first proxy fails, the second proxy will still be able to route requests to the mysql nodes.

#### Broker nodes

There are also two broker jobs (cf-mysql-broker\_z1, cf-mysql-broker\_z2) which should be deployed with one instance each to different subnets.
The brokers each register a route with the router, which load balances requests across the brokers.

<a name="create_manifest"></a>
### Create Manifest and Deploy

1. Download the manifests template.

  * [cf-infrastructure-azure.yml](./cf-infrastructure-azure.yml)
  * [cf-mysql-template.yml](./cf-mysql-template.yml)
  * [sample_azure_stub.yml](./sample_azure_stub.yml)

2. Update the stemcell version.

  You can get the stemcell name and version using `bosh stemcells`.

  ```
  Acting as user 'admin' on 'bosh'
  
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | Name                                     | OS            | Version | CID                                                |
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | bosh-azure-hyperv-ubuntu-trusty-go_agent | ubuntu-trusty | 3169*   | bosh-stemcell-bd80bc85-994d-4271-b2c3-12e530a72a44 |
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  
  (*) Currently in-use
  
  Stemcells total: 1
  ```

  Update `REPLACE_WITH_STEMCELL_VERSION` in `cf-infrastructure-azure.yml`.

  For example:
  ```
  stemcell: &stemcell
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  ```

3. Create a stub file called `cf-mysql-azure-stub.yml` by copying and modifying the [sample_azure_stub.yml](./sample_azure_stub.yml).

  Note you need to replace all the settings that starts with `REPLACE_WITH`.

  You can find your `director_uuid` by running `bosh status --uuid`.

4. Generate the manifest:

  1. You need to install [spiff](https://github.com/cloudfoundry-incubator/spiff).

    ```
    wget https://github.com/cloudfoundry-incubator/spiff/releases/download/v1.0.7/spiff_linux_amd64.zip
    unzip spiff_linux_amd64.zip
    sudo mv spiff /usr/bin/
    ```

  2. Generate `cf-mysql-azure.yml`.

    ```
    $ spiff merge \
      cf-mysql-template.yml \
      cf-infrastructure-azure.yml \
      cf-mysql-azure-stub.yml > cf-mysql-azure.yml
    ```

5. To deploy:

  ```
  $ bosh deployment cf-mysql-azure.yml && bosh -n deploy
  ```

<a name="registering-broker"></a>
## Registering the Service Broker

### BOSH errand

BOSH errands were introduced in version 2366 of the BOSH CLI, BOSH Director, and stemcells.

```
$ bosh run errand broker-registrar
```

Note: the broker-registrar errand will fail if the broker has already been registered, and the broker name does not match the manifest property `jobs.broker-registrar.properties.broker.name`. Use the `cf rename-service-broker` CLI command to change the broker name to match the manifest property then this errand will succeed.

### Manually

1. First register the broker using the `cf` CLI.

  1. You must be logged in as an admin.

    ```
    cf login -a https://api.<system-domain> --skip-ssl-validation # Username: admin; Password: c1oudc0w
    ```

    You should create the organization and space if you login Cloud Foundry for the first time.

    For more information, see [Getting Started with the cf CLI](http://docs.cloudfoundry.org/devguide/installcf/whats-new-v6.html#login).

  2. Create the service broker

    ```
    $ cf create-service-broker p-mysql BROKER_USERNAME BROKER_PASSWORD URL
    ```

    `BROKER_USERNAME` and `BROKER_PASSWORD` are the credentials Cloud Foundry will use to authenticate when making API calls to the service broker. Use the values for manifest properties `jobs.cf-mysql-broker_z1.properties.auth_username` and `jobs.cf-mysql-broker_z1.properties.auth_password`.

    `URL` specifies where the Cloud Controller will access the MySQL broker. Use the value of the manifest property `jobs.cf-mysql-broker_z1.properties.external_host`. By default, this value is set to `p-mysql.<properties.domain>` (in spiff: `"p-mysql." .properties.domain`).

    For more information, see [Managing Service Brokers](http://docs.cloudfoundry.org/services/managing-service-brokers.html).

2. Then [make the service plan public](http://docs.cloudfoundry.org/services/managing-service-brokers.html#make-plans-public).

## Security Groups

Since [cf-release](https://github.com/cloudfoundry/cf-release) v175, applications by default cannot to connect to IP addresses on the private network. This prevents applications from connecting to the MySQL service. To enable access to the service, create a new security group for the IP configured in your manifest for the property `jobs.cf-mysql-broker_z1.mysql_node.host`.

1. Add the rule to a file in the following json format; multiple rules are supported.

  ```
  [
    {
      "destination": "10.0.50.5",
      "protocol": "all"
    }
  ]
  ```

2. Create a security group from the rule file.

  ```shell
  $ cf create-security-group p-mysql rule.json
  ```

3. Enable the rule for all apps

  ```
  $ cf bind-running-security-group p-mysql
  ```

Security group changes are only applied to new application containers; existing apps must be restarted.

<a name="push-app"></a>
## Push an APP using MySQL Service

1. Log on to your dev-box

2. Install CF CLI and the plugin

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  sudo dpkg -i cf.deb
  ```

3. Configure your space

  Run `cat ~/settings | grep cf-ip` to get Cloud Foundry public IP.

  ```
  cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u admin -p c1oudc0w
  cf create-space azure
  cf target -o default_organization -s azure
  ```

4. Sign up for a mysql instance

  Run `cf marketplace` to get the service and plan name.

  ```
  Getting services from marketplace in org default_organization / space azure as admin...
  OK
  
  service   plans        description
  p-mysql   100mb, 1gb   MySQL databases on demand
  ```

  Create a service instance `mysql` with the service name `p-mysql` and the plan `100mb`.

  ```
  cf create-service p-mysql 100mb mysql
  ```

5. Download a sample app

  ```
  sudo apt-get -y git
  git clone https://github.com/cloudfoundry-samples/pong_matcher_go
  ```

6. Push the app

  ```
  cd pong_matcher_go
  cf push
  ```

7. Get the url of the app

  ```
  $ cf apps
  Getting apps in org default_organization / space azure as admin...
  OK

  name     requested state   instances   memory   disk   urls
  gopong   started           1/1         256M     1G     gopong.40.121.149.226.xip.io
  ```

8. Export the test host

  ```
  export HOST=http://gopong.40.121.149.226.xip.io
  ```

9. Verify whether the app works

  ```
  curl -v -H "Content-Type: application/json" -X PUT $HOST/match_requests/firstrequest -d '{"player": "andrew"}'
  curl -v -X GET $HOST/match_requests/firstrequest
  ```

>**NOTE:** More information, please check https://github.com/cloudfoundry-samples/pong_matcher_go.

<a name="deregistering-broker"></a>
## De-registering the Service Broker

The following commands are destructive and are intended to be run in conjuction with deleting your BOSH deployment.

### BOSH errand

BOSH errands were introduced in version 2366 of the BOSH CLI, BOSH Director, and stemcells.

This errand runs the two commands listed in the manual section below from a BOSH-deployed VM.

```
$ bosh run errand broker-deregistrar
```

### Manually

Run the following:

```
$ cf purge-service-offering p-mysql
$ cf delete-service-broker p-mysql
```
