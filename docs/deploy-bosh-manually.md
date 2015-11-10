# Deploy BOSH on Azure Manually

# 1 Setup a Development Environment on Azure

## 1.1 Create a Service Principal

You can refer to the document [**HERE**](./create-service-principal.md) to create a service principal on your tenant.

After this step, you will get:

- **TENANT-ID**
- **CLIENT-ID**
- **CLIENT-SECRET** 

These three values are reusable. Ensure your default subscription is set to the one you used for your service principal.

## 1.2 Create an Azure Resource Group

You will need to determine the deployment location for your group, then create the group in that data center.

```
azure group create <resource-group-name> <location>
```

* resource-group-name:

  * You will use this name for the following commands.
  * Resource group name must uniquely identify the resource group within the subscription.
  * It must be no longer than 80 characters long.
  * It can contain only alphanumeric characters, dash, underscore, opening parenthesis, closing parenthesis, and period.
  * The name cannot end with a period.

* location:

  * Specifies the supported Azure location for the resource group.
  * For more information, see [List all of the available geo-locations](http://azure.microsoft.com/en-us/regions/).

Example:

```
azure group create bosh-res-group "East Asia"
```

You can check whether the resource group is ready for next steps with the following command. You should not proceed to next step until you see "**Provisioning State**" becomes "**Succeeded**" in your output.

```
azure group show <resource-group-name>
```

Example:

```
azure group show bosh-res-group
```

Sample Output:

```
info:    Executing command group show
+ Listing resource groups
+ Listing resources for the group
data:    Id:                  /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/bosh-res-group
data:    Name:                bosh-res-group
data:    Location:            eastasia
data:    Provisioning State:  Succeeded
data:    Tags: null
data:    Resources:  []
data:    Permissions:
data:      Actions: *
data:      NotActions: Microsoft.Authorization/*/Write,Microsoft.Authorization/*/Delete
data:
info:    group show command OK
```

## 1.3 Setup a default Storage Account

### 1.3.1 Create a default Storage Account

```
azure storage account create -l <location> --type <account-type> -g <resource-group-name> <storage-account-name>
```

* storage-account-name:

  * The name for the storage account that is **unique within Azure**.
  * **Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only**.

* account-type:

  Specifies whether the account supports locally-redundant storage, geo-redundant storage, zone-redundant storage, or read access geo-redundant storage.

  Possible values are:

  * LRS   - locally-redundant storage
  * ZRS   - zone-redundant storage
  * GRS   - geo-redundant storage
  * RAGRS - read access geo-redundant storage
  * PLRS  - premium locally-redundant storage

  **NOTE:**

  **ZRS** account cannot be changed to another account type later, and the other account types cannot be changed to **ZRS**. The same goes for **PLRS** accounts. You can click [**HERE**](http://azure.microsoft.com/en-us/pricing/details/storage/) to learn more about the type of Azure storage account.

Example:

```
azure storage account create -l "East Asia" --type GRS -g bosh-res-group xxxxx
```

**NOTE:** Even if you see error in the response of creating the storage account, you still can check whether the storage account is created successfully under your resource group with the following command.

```
azure storage account show -g <resource-group-name> <storage-account-name>
```

Example:

```
azure storage account show -g bosh-res-group xxxxx
```

Sample Output:

```
+ Getting storage account
data:    Name: xxxxx
data:    Url: /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/bosh-res-group/providers/Microsoft.Storage/storageAccounts/xxxxx
data:    Type: Standard_GRS
data:    Resource Group: bosh-res-group
data:    Location: East Asia
data:    Provisioning State: Succeeded
data:    Primary Location: East Asia
data:    Primary Status: available
data:    Secondary Location: Southeast Asia
data:    Creation Time: 2015-11-02T05:35:27.0572370Z
data:    Primary Endpoints: blob https://xxxxx.blob.core.windows.net/
data:    Primary Endpoints: queue https://xxxxx.queue.core.windows.net/
data:    Primary Endpoints: table https://xxxxx.table.core.windows.net/
info:    storage account show command OK
```

### 1.3.2 List storage account keys

```
azure storage account keys list -g <resource-group-name> <storage-account-name>
```

Sample Output:

```
info:    Executing command storage account keys list
Resource group name: bosh-res-group
+ Getting storage account keys
data:    Primary: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
data:    Secondary: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
info:    storage account keys list command OK
```

You can get the primary key as your `storage-account-key`.

### 1.3.3 Create Containers

You need to create the following containers in the storage account:

* bosh
  * Stores the OS and data disks for BOSH VMs
* stemcell
  * Stores the stemcells
  * To support multiple storage accounts, you need to set the permission of the container `stemcell` as `Public read access for blobs only`

```
azure storage container create -a <storage-account-name> -k <storage-account-key> bosh
azure storage container create -a <storage-account-name> -k <storage-account-key> -p Blob stemcell
```

You can list the containers with the following command:

```
azure storage container list -a <storage-account-name> -k <storage-account-key>
```

Sample Output:

```
info:    Executing command storage container list
+ Getting storage containers
data:    Name      Public-Access  Last-Modified
data:    --------  -------------  -----------------------------
data:    bosh      Off            Mon, 02 Nov 2015 01:52:33 GMT
data:    stemcell  Blob           Mon, 02 Nov 2015 02:02:59 GMT
info:    storage container list command OK
```

### 1.3.4 Create Tables

To support multiple storage accounts, you need to create the following tables in the default storage account:

* stemcells
  * Stores the metadata of stemcells in multiple storage accounts

```
azure storage table create -a <storage-account-name> -k <storage-account-key> stemcells
```

You can list the tables with the following command:

```
azure storage table list -a <storage-account-name> -k <storage-account-key>
```

Sample Output:

```
info:    Executing command storage table list
+ Getting storage tables
data:    Name
data:    ---------
data:    stemcells
info:    storage table list command OK
```

## 1.4 Create a Public IP for Cloud Foundry

### 1.4.1 Create the Public IP

```
azure network public-ip create -g <resource-group-name> -l <location> -a Static -n <public-ip-name>
```

Example:

```
azure network public-ip create -g bosh-res-group -l "East Asia" -a Static -n public-ip-for-cf
```

<a name="get_public_ip"></a>
### 1.4.2 Get the Public IP Address

```
azure network public-ip show -g <resource-group-name> -n <public-ip-name>
```

Example:

```
azure network public-ip show -g bosh-res-group -n public-ip-for-cf
```

Sample Output:

```
info:    Executing command network public-ip show
+ Looking up the public ip "public-ip-for-cf"
data:    Id                              : /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/bosh-res-group/providers/Microsoft.Network/publicIPAddresses/public-ip-for-cf
data:    Name                            : public-ip-for-cf
data:    Type                            : Microsoft.Network/publicIPAddresses
data:    Location                        : eastasia
data:    Provisioning state              : Succeeded
data:    Allocation method               : Static
data:    Idle timeout                    : 4
data:    IP Address                      : 23.99.103.110
info:    network public-ip show command OK
```

The value of **IP Address** in the output is your **reserved IP for Cloud Foundry**.

## 1.5 Create a Virtual Network

1. Create a Virtual Network

  ```
  azure network vnet create -g <resource-group-name> -n <virtual-network-name> -l <location> -a <virtual-network-cidr>
  ```

  Options:

  * virtual-network-name: Names must start with a letter or number, and must contain only letters, numbers, or dashes. Spaces are not allowed.
  * virtual-network-cidr: The address space network mask in CIDR format for the virtual network.

  Example:

  ```
  azure network vnet create -g bosh-res-group -n boshvnet-crp -l "East Asia" -a 10.0.0.0/8
  ```

2. Create two subnets in the Virtual Network

  ```
  azure network vnet subnet create -g <resource-group-name> -e <virtual-network-name> -n <bosh-subnet-name> -a <bosh-subnet-cidr>
  azure network vnet subnet create -g <resource-group-name> -e <virtual-network-name> -n <cloudfoundry-subnet-name> -a <cloudfoundry-subnet-cidr>
  ```

  Options:

  * bosh-subnet-name: The name of the subnet where VMs for BOSH will locate.
  * bosh-subnet-cidr: The subnet network mask in CIDR format for bosh subnet.
  * cloudfoundry-subnet-name: The name of bosh subnet where VMs for Cloud Foundry will locate.
  * cloudfoundry-subnet-cidr: The subnet network mask in CIDR format for Cloud Foundry.

  You need to create two subnets:

  * Name: BOSH, CIDR: 10.0.0.0/20. For BOSH VMs.
  * Name: CloudFoundry, CIDR: 10.0.16.0/20. For Cloud Foundry VMs.

  Example:

  ```
  azure network vnet subnet create -g bosh-res-group -e boshvnet-crp -n BOSH -a 10.0.0.0/20
  azure network vnet subnet create -g bosh-res-group -e boshvnet-crp -n CloudFoundry -a 10.0.16.0/20
  ```

3. Verify the Virtual Network

  You can check whether the virtual network is created successfully under your resource group with the following command.

  ```
  azure network vnet show -g <resource-group-name> -n <virtual-network-name>
  ```

  Example:

  ```
  azure network vnet show -g bosh-res-group -n boshvnet-crp
  ```

  Sample Output:

  ```
  info:    Executing command network vnet show
  + Looking up virtual network "boshvnet-crp"
  data:    Id                              : /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/bosh-res-group/providers/Microsoft.Network/virtualNetworks/boshvnet-crp
  data:    Name                            : boshvnet-crp
  data:    Type                            : Microsoft.Network/virtualNetworks
  data:    Location                        : eastasia
  data:    ProvisioningState               : Succeeded
  data:    Address prefixes:
  data:      10.0.0.0/8
  data:    Subnets:
  data:      Name                          : BOSH
  data:      Address prefix                : 10.0.0.0/20
  data:
  data:      Name                          : CloudFoundry
  data:      Address prefix                : 10.0.16.0/20
  data:
  info:    network vnet show command OK
  ```

## 1.6 Setup a dev-box

### 1.6.1 Create a virtual machine

You can create a virtual machine based on **Ubuntu Server 14.04 LTS** on Azure Portal. The VM will be a **dev-box** to deploy BOSH and Cloud Foundry.

**NOTE:**

* As a temporary limitation, **currently the dev-box should be on Azure and in the same virutal network with BOSH VMs and CF VMs**. And the dev-box should be in the subnet `BOSH`.
* Select **Resource Manager** as the deployment model.
* **(RECOMMENDED)** Avoid using the private IP addresses **10.0.0.4** and **10.0.16.4** for your dev-box. On Azure Portal, you can manually change the private IP address to a default value **10.0.0.100** after the dev-box is created. Afthe the IP address is changed, the dev-box may reboot.
* **(NOT RECOMMENDED)** If you would like to use **10.0.0.4** or **10.0.16.4** for your dev-box, you need to change the IP address in example YAML files to stay the same.

### 1.6.2 Setup your dev-box

```
cd ~
echo "Start to update package lists from repositories..."
sudo apt-get update

echo "Start to update install prerequisites..."
sudo apt-get install -y build-essential ruby2.0 ruby2.0-dev libxml2-dev libsqlite3-dev libxslt1-dev libpq-dev libmysqlclient-dev zlibc zlib1g-dev openssl libxslt-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev sqlite3 libffi-dev

sudo rm /usr/bin/ruby /usr/bin/gem /usr/bin/irb /usr/bin/rdoc /usr/bin/erb
sudo ln -s /usr/bin/ruby2.0 /usr/bin/ruby
sudo ln -s /usr/bin/gem2.0 /usr/bin/gem
sudo ln -s /usr/bin/irb2.0 /usr/bin/irb
sudo ln -s /usr/bin/rdoc2.0 /usr/bin/rdoc
sudo ln -s /usr/bin/erb2.0 /usr/bin/erb
sudo gem update --system
sudo gem pristine --all

echo "Start to install bosh_cli..."
sudo gem install bosh_cli -v 1.3016.0 --no-ri --no-rdoc

echo "Start to install bosh-init..."
wget –O bosh-init https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.51-linux-amd64
chmod +x ./bosh-init-*
sudo mv ./bosh-init-* /usr/local/bin/bosh-init

echo "Finish"
```

# 2 Deploy BOSH

<a name="configure_bosh_yml"></a>
## 2.1 Configure

1. Create a Deployment Manifest

  The deployment manifest is a YAML file that defines the components and properties of the Cloud Foundry deployment. You need to create a deployment manifest file named **bosh.yml** in your dev-box based on the template below.

  ```
  ---
  name: bosh

  releases:
  - name: bosh
    url: BOSH-FOR-AZURE-URL
    sha1: BOSH-FOR-AZURE-SHA1
  - name: bosh-azure-cpi
    url: BOSH-AZURE-CPI-URL
    sha1: BOSH-AZURE-CPI-SHA1

  networks:
  - name: private
    type: manual
    subnets:
    - range: 10.0.0.0/24
      gateway: 10.0.0.1
      dns: [8.8.8.8]
      cloud_properties:
        virtual_network_name: VNET-NAME
          # <--- Replace VNET-NAME with your virtual network name
        subnet_name: SUBNET-NAME
          # <--- Replace SUBNET-NAME with subnet name for your BOSH VM

  resource_pools:
  - name: vms
    network: private
    stemcell:
      url: STEMCELL-FOR-AZURE-URL
      sha1: STEMCELL-FOR-AZURE-SHA1
    cloud_properties:
      instance_type: Standard_D1

  disk_pools:
  - name: disks
    disk_size: 25_000

  jobs:
  - name: bosh
    templates:
    - {name: nats, release: bosh}
    - {name: redis, release: bosh}
    - {name: postgres, release: bosh}
    - {name: blobstore, release: bosh}
    - {name: director, release: bosh}
    - {name: health_monitor, release: bosh}
    - {name: registry, release: bosh}
    - {name: cpi, release: bosh-azure-cpi}

    instances: 1
    resource_pool: vms
    persistent_disk_pool: disks

    networks:
    - {name: private, static_ips: [10.0.0.4], default: [dns, gateway]}

    properties:
      nats:
        address: 127.0.0.1
        user: nats
        password: nats-password

      redis:
        listen_addresss: 127.0.0.1
        address: 127.0.0.1
        password: redis-password

      postgres: &db
        host: 127.0.0.1
        user: postgres
        password: postgres-password
        database: bosh
        adapter: postgres

      registry:
        address: 10.0.0.4
        host: 10.0.0.4
        db: *db
        http: {user: admin, password: admin, port: 25777}
        username: admin
        password: admin
        port: 25777

      blobstore:
        address: 10.0.0.4
        port: 25250
        provider: dav
        director: {user: director, password: director-password}
        agent: {user: agent, password: agent-password}

      director:
        address: 127.0.0.1
        name: bosh
        db: *db
        cpi_job: cpi
        enable_snapshots: true

      hm:
        http: {user: hm, password: hm-password}
        director_account: {user: admin, password: admin}

      azure: &azure
        environment: AzureCloud
        subscription_id: SUBSCRIPTION-ID
          # <--- Replace SUBSCRIPTION-ID with your subscription id
        storage_account_name: STORAGE-ACCOUNT-NAME
          # <--- Replace STORAGE-ACCOUNT-NAME with your storage account name
        resource_group_name: RESOURCE-GROUP-NAME
          # <--- Replace RESOURCE-GROUP-NAME with your resource group name
        tenant_id: TENANT-ID
          # <--- Replace TENANT-ID with your tenant id of the service principal
        client_id: CLIENT-ID
          # <--- Replace CLIENT-ID with your client id of the service principal
        client_secret: CLIENT-SECRET
          # <--- Replace CLIENT-SECRET with your client secret of the service principal
        ssh_user: vcap
        ssh_certificate: SSH-CERTIFICATE
          # <--- Replace SSH-CERTIFICATE with the content of your ssh certificate

      agent: {mbus: "nats://nats:nats-password@10.0.0.4:4222"}

      ntp: &ntp [0.north-america.pool.ntp.org]

  cloud_provider:
    template: {name: cpi, release: bosh-azure-cpi}

    ssh_tunnel:
      host: 10.0.0.4
      port: 22
      user: vcap # The user must be as same as above ssh_user
      private_key: ~/bosh # Path relative to this manifest file

    mbus: https://mbus-user:mbus-password@10.0.0.4:6868

    properties:
      azure: *azure
      agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}
      blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}
      ntp: *ntp
  ```

2. Update **bosh.yml**

  * Replace **BOSH-FOR-AZURE-URL**, **BOSH-FOR-AZURE-SHA1**, **BOSH-AZURE-CPI-URL**, **BOSH-AZURE-CPI-SHA1**, **STEMCELL-FOR-AZURE-URL** and **STEMCELL-FOR-AZURE-SHA1** with the values in the example file [**bosh.yml**](https://github.com/Azure/azure-quickstart-templates/blob/master/bosh-setup/bosh.yml).

  * Replace the following items with your pre-defined value just created above: **VNET-NAME**, **SUBNET-NAME**, **SUBSCRIPTION-ID**, **STORAGE-ACCOUNT-NAME**, **RESOURCE-GROUP-NAME**, **TENANT-ID**, **CLIENT-ID** and **CLIENT-SECRET** properties.

  * You can use the following commands to generate the new private key `~/bosh` and certificate `~/bosh.pem` for testing.

    ```
    openssl genrsa -out ~/bosh 2048
    openssl req -new -x509 -days 365 -key ~/bosh -out ~/bosh.pem
    chmod 400 ~/bosh
    ```

  * **SSH-CERTIFICATE** should be the contents of `~/bosh.pem`.

    Example:

    ```
    ssh_certificate: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAJo9AXFrnu5CMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
      BAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEwHwYDVQQKDBhJbnRlcm5ldCBX
      aWRnaXRzIFB0eSBMdGQwHhcNMTUxMTAyMDY1ODMwWhcNMTYxMTAxMDY1ODMwWjBF
      MQswCQYDVQQGEwJBVTETMBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UECgwYSW50
      ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
      CgKCAQEAxYprxo690XyLTwMe2VXeu4tseLuKeksPvyBV0VAOGY5Y5fkhz1btJ1dG
      tcAyzNrWfwGp7Vu8T5U6mFXGE72efqcXrNVaBlajKXF79p1qZfsylvxjGx0a62Kn
      sC6cVc37B9210nNiwq6W6hi7kHjgYd7GILIidxcPVZpnAk/s+e7X35YhLhquFbdy
      TQmOT36XZKreaLFcv1Fi2ZyvjovLHFz9GkD5sBfg2NkrdTeqFi/9GMzsaWTP8pou
      NQ8hqlcWUA3XNZLNv8bo21Mc0qOHEXfkmyvFANlgWQPWWbE4Quo4lJvkMN6jYBmJ
      lWEnc/R8Si6hmRdjgXQ1v2CoZ9tZ4QIDAQABo1AwTjAdBgNVHQ4EFgQUDY15m/TC
      MCUs2wNTcabc7YiAX4owHwYDVR0jBBgwFoAUDY15m/TCMCUs2wNTcabc7YiAX4ow
      DAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAm+VTaA00dMvpX5aMyJLM
      RQoJonzpU0fZEKSQWiG2obzzi9NkwZR+aXQbIM3/9D+u3P8GPd0grr/UbrcP2wxH
      qj09PrsNNa8ehOTxvAjDM6cj+ozheneGGiMtZveJZYjN59UF7pBDmoTgNB0JRXYU
      Feqx2/uLUrsrz+GCc0i+huc7vmOiI+uSsj1LD1EkKRg783DO/XnQW7KWUhCuLNXi
      8Wqhq8rUJkAyLDuEBu3TnCdCJynh3hXOl1JyHvPUMb6J5ts+e4bV1gfUjQy3at1r
      HOKDAJ8TzxpxhVEt+LxovCh/+vdziuaLsp1rPN/5FXTZQQDQXyfSvPc2Ygm/MwOG
      vA==
      -----END CERTIFICATE-----
    ```

    **NOTE:**
    * **Never use the certificate in the example.**

## 2.2 Deploy

First, optionally, use below commands to set debug level if you want to collect more logs.

```
export BOSH_INIT_LOG_LEVEL='Debug'
export BOSH_INIT_LOG_PATH='./run.log'
```

Deploy:

```
bosh-init deploy bosh.yml
```

**NOTE:**

* Never use root to do it.
* More verbose logs are written to `~/run.log`.

# 3 Setup DNS

This step is optional. If you have a pre-configured DNS server for the domain name, you can skip this step. Otherwise, you can download [setup_dns.py](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/bosh-setup/setup_dns.py) and use the commands below to configure your dev-box as a DNS server for testing quickly.

```
sudo python setup_dns.py -d cf.azurelovecf.com -i 10.0.16.4 -e <reserved-ip-for-cloud-foundry> -n <public-ip-of-dev-box>
```

* reserved-ip-for-cloud-foundry:

  The reserved public IP address **RESERVED-IP** for Cloud Foundry.

* public-ip-of-dev-box:

  The public IP address of your dev-box. If your dev-box reboots, its public IP address may change. You need to manually update it in **/etc/bind/cf.com.wan**.
