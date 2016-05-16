# Deploy BOSH on Azure Manually

# 1 Setup a Development Environment on Azure

## 1.1 Create an Azure Resource Group

You will need to determine the deployment location for your group, then create the group in that data center.

```
azure group create --name $resource_group_name --location $location
```

* resource_group_name:

  * You will use this name for the following commands.
  * Resource group name must uniquely identify the resource group within the subscription.
  * It must be no longer than 80 characters long.
  * It can contain only alphanumeric characters, dash, underscore, opening parenthesis, closing parenthesis, and period.
  * The name cannot end with a period.

* location:

  * Specifies the supported Azure location for the resource group.
  * For more information, see [List all of the available geo-locations](http://azure.microsoft.com/en-us/regions/). For `AzureChinaCloud`, you should only use the regions in China.

Example:

```
azure group create --name bosh-res-group --location "East Asia"
```

You can check whether the resource group is ready for next steps with the following command. You should not proceed to next step until you see "**Provisioning State**" becomes "**Succeeded**" in your output.

```
azure group show --name $resource_group_name
```

Example:

```
azure group show --name bosh-res-group
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

<a name="setup-a-default-storage-account"/>
## 1.2 Setup a default Storage Account

### 1.2.1 Create a default Storage Account

```
azure storage account create --location $location --type $account_type --resource-group $resource_group_name $storage_account_name
```

* storage_account_name:

  * The name for the storage account that is **unique within Azure**.
  * **Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only**.

* account_type:

  Specifies whether the account supports locally-redundant storage, geo-redundant storage, zone-redundant storage, or read access geo-redundant storage.

  Possible values are:

  * LRS   - locally-redundant storage
  * ZRS   - zone-redundant storage
  * GRS   - geo-redundant storage
  * RAGRS - read access geo-redundant storage
  * PLRS  - premium locally-redundant storage

  >**NOTE:** **ZRS** account cannot be changed to another account type later, and the other account types cannot be changed to **ZRS**. The same goes for **PLRS** accounts. You can click [**HERE**](http://azure.microsoft.com/en-us/pricing/details/storage/) to learn more about the type of Azure storage account.

Example:

```
azure storage account create --location "East Asia" --type GRS --resource-group bosh-res-group xxxxx
```

>**NOTE:** Even if you see error in the response of creating the storage account, you still can check whether the storage account is created successfully under your resource group with the following command.

```
azure storage account show --resource-group $resource_group_name $storage_account_name
```

Example:

```
azure storage account show --resource-group bosh-res-group xxxxx
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

### 1.2.2 List storage account keys

```
azure storage account keys list --resource-group $resource_group_name $storage_account_name
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

You can get the primary key as your `storage_account_key`.

### 1.2.3 Create Containers

You need to create the following containers in the storage account:

* bosh
  * Stores the OS and data disks for BOSH VMs
* stemcell
  * Stores the stemcells
  * To support multiple storage accounts, you need to set the permission of the container `stemcell` as `Public read access for blobs only`

```
azure storage container create --account-name $storage_account_name --account-key $storage_account_key --container bosh
azure storage container create --account-name $storage_account_name --account-key $storage_account_key --permission Blob --container stemcell
```

You can list the containers with the following command:

```
azure storage container list --account-name $storage_account_name --account-key $storage_account_key
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

### 1.2.4 Create Tables

To support multiple storage accounts, you need to create the following tables in the default storage account:

* stemcells
  * Stores the metadata of stemcells in multiple storage accounts

```
azure storage table create --account-name $storage_account_name --account-key $storage_account_key --table stemcells
```

You can list the tables with the following command:

```
azure storage table list --account-name $storage_account_name --account-key $storage_account_key
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

## 1.3 Create a Public IP for Cloud Foundry

### 1.3.1 Create the Public IP

```
azure network public-ip create --resource-group $resource_group_name --location $location --allocation-method Static --name $public_ip_name
```

Example:

```
azure network public-ip create --resource-group bosh-res-group --location "East Asia" --allocation-method Static --name public-ip-for-cf
```

<a name="get_public_ip"></a>
### 1.3.2 Get the Public IP Address

```
azure network public-ip show --resource-group $resource_group_name --name $public_ip_name
```

Example:

```
azure network public-ip show --resource-group bosh-res-group --name public-ip-for-cf
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

## 1.4 Create a Virtual Network

### 1.4.1 Create a Virtual Network

```
azure network vnet create --resource-group $resource_group_name --name $virtual_network_name --location $location --address-prefixes $virtual_network_cidr
```

Options:

* virtual_network_name: Names must start with a letter or number, and must contain only letters, numbers, or dashes. Spaces are not allowed.
* virtual_network_cidr: The address space network mask in CIDR format for the virtual network.

Example:

```
azure network vnet create --resource-group bosh-res-group --name boshvnet-crp --location "East Asia" --address-prefixes 10.0.0.0/8
```

### 1.4.2 Create subnets in the Virtual Network

```
azure network vnet subnet create --resource-group $resource_group_name --vnet-name $virtual_network_name --name $bosh_subnet_name --address-prefix $bosh_subnet_cidr
azure network vnet subnet create --resource-group $resource_group_name --vnet-name $virtual_network_name --name $cloudfoundry_subnet_name --address-prefix $cloudfoundry_subnet_cidr
azure network vnet subnet create --resource-group $resource_group_name --vnet-name $virtual_network_name --name $diego_subnet_name --address-prefix $diego_subnet_cidr
```

Options:

* bosh_subnet_name: The name of the subnet where VMs for BOSH will locate.
* bosh_subnet_cidr: The subnet network mask in CIDR format for bosh subnet.
* cloudfoundry_subnet_name: The name of the subnet where VMs for Cloud Foundry will locate.
* cloudfoundry_subnet_cidr: The subnet network mask in CIDR format for Cloud Foundry.
* diego_subnet_name: The name of diego subnet where VMs for Diego will locate.
* diego_subnet_cidr: The subnet network mask in CIDR format for Diego.

You need to create below subnets:

* Name: BOSH, CIDR: 10.0.0.0/24. For BOSH VMs.
* Name: CloudFoundry, CIDR: 10.0.16.0/20. For Cloud Foundry VMs.
* Name: Diego, CIDR: 10.0.32.0/20. For Diego VMs.

Example:

```
azure network vnet subnet create --resource-group bosh-res-group --vnet-name boshvnet-crp --name BOSH --address-prefix 10.0.0.0/24
azure network vnet subnet create --resource-group bosh-res-group --vnet-name boshvnet-crp --name CloudFoundry --address-prefix 10.0.16.0/20
azure network vnet subnet create --resource-group bosh-res-group --vnet-name boshvnet-crp --name Diego --address-prefix 10.0.32.0/20
```

### 1.4.3 Verify the Virtual Network

You can check whether the virtual network is created successfully under your resource group with the following command.

```
azure network vnet show --resource-group $resource_group_name --name $virtual_network_name
```

Example:

```
azure network vnet show --resource-group bosh-res-group --name boshvnet-crp
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
data:      Address prefix                : 10.0.0.0/24
data:
data:      Name                          : CloudFoundry
data:      Address prefix                : 10.0.16.0/20
data:
data:      Name                          : Diego
data:      Address prefix                : 10.0.32.0/20
data:
info:    network vnet show command OK
```

### 1.4.4 Config Network Security Groups

 Network security group (NSG) contains a list of Access Control List (ACL) rules that allow or deny network traffic to your VM instances in a Virtual Network. NSGs can be associated with either subnets or individual VM instances within that subnet. When a NSG is associated with a subnet, the ACL rules apply to all the VM instances in that subnet. In addition, traffic to an individual VM can be restricted further by associating a NSG directly to that VM.
You can learn more information [here](https://azure.microsoft.com/en-us/documentation/articles/virtual-networks-nsg/).

1. Create Network Security Group

  ```
  azure network nsg create --resource-group $resource_group_name --location $location --name $nsg_name_for_bosh
  azure network nsg create --resource-group $resource_group_name --location $location --name $nsg_name_for_cloudfoundry
  ```

  * nsg_name_for_bosh: The name of the network security group for BOSH subnet.
  * nsg_name_for_cloudfoundry: The name of the network security group for CloudFoundry subnet.

  Example:

  ```
  azure network nsg create --resource-group bosh-res-group --location "East Asia" --name nsg-bosh
  azure network nsg create --resource-group bosh-res-group --location "East Asia" --name nsg-cf
  ```

2. Create Network Security Rules for BOSH Subnet

  ```
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_bosh --access Allow --protocol Tcp --direction Inbound --priority 200 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'ssh' --destination-port-range 22
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_bosh --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-agent' --destination-port-range 6868
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_bosh --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-director' --destination-port-range 25555
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_bosh --access Allow --protocol '*' --direction Inbound --priority 203 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'dns' --destination-port-range 53
  ```

  Example:

  ```
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 200 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'ssh' --destination-port-range 22
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-agent' --destination-port-range 6868
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-director' --destination-port-range 25555
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-bosh --access Allow --protocol '*' --direction Inbound --priority 203 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'dns' --destination-port-range 53
  ```

3. Create Network Security Rules for CloudFoundry Subnet

  ```
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_cloudfoundry --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-https' --destination-port-range 443
  azure network nsg rule create --resource-group $resource_group_name --nsg-name $nsg_name_for_cloudfoundry --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-log' --destination-port-range 4443
  ```

  Example:

  ```
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-cf --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-https' --destination-port-range 443
  azure network nsg rule create --resource-group bosh-res-group --nsg-name nsg-cf --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-log' --destination-port-range 4443
  ```

## 1.5 Setup a dev-box

### 1.5.1 Create a virtual machine

1. Create the network interface and public IP for the dev-box

  ```
  azure network nic create --resource-group $resource_group_name --location $location --name $nic_name --private-ip-address 10.0.0.100 --subnet-vnet-name $virtual_network_name --subnet-name $bosh_subnet_name
  azure network public-ip create --resource-group $resource_group_name --location $location --allocation-method Dynamic --name $public_ip_devbox
  azure network nic set --public-ip-name $public_ip_devbox --resource-group $resource_group_name --name $nic_name
  ```

2. You can use the following commands to generate the SSH key pair for testing

  ```
  ssh-keygen -t rsa -f ~/devbox -P "" -C ""
  chmod 400 ~/devbox
  ```

3. Query the image URN

  ```
  azure vm image list --location $location --publisher canonical --offer UbuntuServer
  ```

  Sample output:

  ```
  data:    Publisher  Offer         Sku                OS     Version          Location  Urn                                     
  data:    ---------  ------------  -----------------  -----  ---------------  --------  --------------------------------------------------------
  data:    canonical  UbuntuServer  12.04.3-LTS        Linux  12.04.201401270  eastus    canonical:UbuntuServer:12.04.3-LTS:12.04.201401270
  ```

  Get the `Urn` which you like from the output as the parameter value for `--image-urn`. `canonical:UbuntuServer:14.04.3-LTS:latest` is recommended.

4. Create the VM

  ```
  azure vm create --resource-group $resource_group_name --name $devbox_name --location $location --os-type linux --nic-name $nic_name --vnet-name $virtual_network_name --vnet-subnet-name $bosh_subnet_name --storage-account-name $storage_account_name --image-urn $urn --ssh-publickey-file ~/devbox.pub --admin-username $username
  ```

  Example:

  ```
  azure network nic create --resource-group bosh-res-group --location "East Asia" --name devbox-nic --private-ip-address 10.0.0.100 --subnet-vnet-name boshvnet-crp --subnet-name BOSH
  azure network public-ip create --resource-group bosh-res-group --location "East Asia" --allocation-method Dynamic --name devbox-ip
  azure network nic set --public-ip-name devbox-ip --resource-group bosh-res-group --name devbox-nic
  azure vm create --resource-group bosh-res-group --name bosh-res-group-devbox --location "East Asia" --os-type linux --nic-name devbox-nic --vnet-name boshvnet-crp --vnet-subnet-name BOSH --storage-account-name yourstorageaccountname --image-urn canonical:UbuntuServer:14.04.3-LTS:latest --ssh-publickey-file ~/devbox.pub --admin-username azureuser
  ```

>**NOTE:**
  * As a temporary limitation, **currently the dev-box should be on Azure and in the same virtual network with BOSH VMs and CF VMs**. And the dev-box should be in the subnet `BOSH`.
  * If Azure CLI failed to create a linux VM because of unsupported api-versions, please use Azure CLI v0.9.18. [Azure/azure-xplat-cli/#2824](https://github.com/Azure/azure-xplat-cli/issues/2824).

### 1.5.2 Login your dev-box

You can find the public IP address of the dev-box on Azure Portal or using the following command.

```
azure network public-ip show --resource-group $resource_group_name --name $public_ip_devbox
```

Login your dev-box with the `username` and the private key which you generated in the previous section.

### 1.5.3 Setup your dev-box

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
```

If the environment is `AzureChinaCloud`, you need to update the ruby gems sources.

```
sudo gem sources --remove https://rubygems.org/
sudo gem sources --add https://ruby.taobao.org/
sudo gem sources --add https://gems.ruby-china.org
```

Then install `bosh_cli` and `bosh-init`.

```
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

  The deployment manifest is a YAML file that defines the components and properties of the BOSH deployment. You need to create a deployment manifest file named **bosh.yml** in your dev-box based on the [**template**](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/bosh-setup/manifests/bosh.yml).

2. Update **bosh.yml**

  * Replace the releases and stemcells.

    * **REPLACE_WITH_BOSH_RELEASE_URL** and **REPLACE_WITH_BOSH_RELEASE_SHA1**
    * **REPLACE_WITH_BOSH_AZURE_CPI_RELEASE_URL** and **REPLACE_WITH_BOSH_AZURE_CPI_RELEASE_SHA1**
    * **REPLACE_WITH_STEMCELL_URL** and **REPLACE_WITH_STEMCELL_SHA1**

  * Replace the following items with your pre-defined value just created above:

    * **REPLACE_WITH_SUBNET_ADDRESS_RANGE_FOR_BOSH**(e.g., 10.0.0.0/24)
    * **REPLACE_WITH_GATEWAY_IP**(e.g., 10.0.0.1)
    * **REPLACE_WITH_VNET_NAME**
    * **REPLACE_WITH_SUBNET_NAME_FOR_BOSH**
    * **REPLACE_WITH_BOSH_DIRECTOR_IP**
    * **REPLACE_WITH_ENVIRONMENT**
    * **REPLACE_WITH_SUBSCRIPTION_ID**
    * **REPLACE_WITH_DEFAULT_STORAGE_ACCOUNT_NAME**
    * **REPLACE_WITH_RESOURCE_GROUP_NAME**
    * **REPLACE_WITH_TENANT_ID**
    * **REPLACE_WITH_CLIENT_ID**
    * **REPLACE_WITH_CLIENT_SECRET**
    * **REPLACE_WITH_NSG_NAME_FOR_BOSH**

  * You can use the following commands to generate the SSH key pair for testing.

    ```
    ssh-keygen -t rsa -f ~/bosh -P "" -C ""
    chmod 400 ~/bosh
    ```

  * **REPLACE_WITH_SSH_PUBLIC_KEY** should be the contents of `~/bosh.pub`.

    Example:

    ```
    ssh_public_key: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh7LrwWCYhdgpIcX+cBcwVuXMSKfcybMNrRfy2hsNXmKrqd4kJMKXS43njuv+ydrfGo1HO4ZcRqdyku+u5N78jhzilV9bOpgr57LnrFs7vIFExhWpkqJXC7abVScN8bZ8QlD3YAbgWEtS/2G1dmNbihkuE+2ICLpmPixNDPIGCQlNmHp0O7Z97jnX9zETMhrHRpksDslpeqNC4mzY6KIIixbwXOYrkMrtlupOKIi/qNqlbLc/nX6ltRk9ujlC0/XsmMXrnTFUM2s4p7sqbHvyDEOFlc42VAIsDH7DerPjVHMBgSAiXd1Z9B5uzPahW37ZKikYA9U2PC3D1TqgTUC7N
    ```

  * **REPLACE_WITH_KEEP_UNREACHABLE_VMS** should be true if you want to debug after task fails. Otherwise set it to false.

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

>**NOTE:**
  * Never use root to perform these steps.
  * More verbose logs are written to `~/run.log`.
  * If you hit any issue, please see [**troubleshooting**](../../additional-information/troubleshooting.md), [**known issues**](../../additional-information/known-issues.md) and [**migration**](../../additional-information/migration.md). If it does not work, you can file an issue [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues).
