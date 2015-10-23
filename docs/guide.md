# Guide to Deploy Cloud Foundry on Azure #

# Overview #

This document describes the steps to setup and deploy Cloud Foundry on Azure, including preparing the Azure environment and deploying Cloud Foundry on Azure.

Note this document provides the setup and deploy steps using step by step standalone commands; for alternation steps using pre-created Azure Resource Manager template, please reference [the template guide](https://github.com/Azure/bosh-azure-cpi-release/blob/master/docs/template-guide.md).


# Updates from last version #

Following are updates from [Preview version of Cloud Foundry on Azure](http://azure.microsoft.com/blog/2015/05/29/try-cloud-foundry-on-azure-today/).

•   Update Azure CPI code to pick up version 2972 from Cloud Foundry main branch

•   Support [bosh-init](https://github.com/cloudfoundry/bosh-init)

•   Support creating multiple Cloud Foundry VMs

•   Support [Bosh snapshot](https://bosh.io/docs/snapshots.html)

•   Remove NodeJS code and related dependencies, keeping all Azure CPI code Ruby based



# Prerequisites #

•   [Creating an Azure account](https://azure.microsoft.com/en-us/pricing/free-trial/)

•   Installing and Configuring [Azure CLI](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli/)





## 1. Create a Deployment Manifest ##

The deployment manifest is a YAML file that defines the components and properties of the Cloud Foundry deployment. You need to create a deployment manifest file named bosh.yml in your dev-box based on the template below.

You need to replace **BOSH-FOR-AZURE-URL**, **BOSH-FOR-AZURE-SHA1**, **BOSH-AZURE-CPI-URL**, **BOSH-AZURE-CPI-SHA1**, **STEMCELL-FOR-AZURE-URL** and **STEMCELL-FOR-AZURE-SHA1** with the values in the example file [bosh.yml](http://cloudfoundry.blob.core.windows.net/misc/bosh.yml).


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
        instance_type: Standard_A2

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



# 2	Prepare an Azure Environment #

To configure your Azure account for BOSH and Cloud Foundry:

1.  Prepare Azure CLI

2.  Create a Service Principal

3.  Create an Azure Resource Group

4.  Create an Azure Storage Account

5.  Create a Public IP for Cloud Foundry

6.  Create a Virtual Network


## 2.1 Prepare Azure CLI ##

Install and configure Azure CLI following the documentation [here](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli/). If you are using Windows, make sure you use **command line** but not PowerShell to run the Azure CLI. It is suggested you run the CLI commands here using Ubuntu Server 14.04 LTS or Windows 8.1.

### 2.1.2  Configure Azure CLI ###

#### 2.1.2.1  Set mode to Azure Resource Management ####

	azure config mode arm


#### 2.1.2.2   Login ####

Please note this login method requires a work or school account.
If you do not currently have a work or school account, and are using a personal account to log in to your Azure subscription, you can easily create a work or school account, following this [guide](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-connect/). And then log in with your created work account to execute below commands.

If you have enabled MFA, creating the service principal may fail. You need to disable MFA and try again.

	#Enter your Microsoft account credentials when prompted.

	azure login


## 2.2	Creating a Service Principal ##

Azure CPI provisions resources in Azure using the Azure Resource Manager (ARM) APIs. We use a Service Principal account to give Azure CPI the access to proper resources.

### 2.2.1	Set Default Subscription ###

Ensure your default subscription is set to the one you want to create your service principal.

First check whether you have multiple subscriptions:

	azure account list --json

Below is a sample output from the command.

You can get **SUBSCRIPTION-ID** from the column "Id" in the result.

You can get **TENANT-ID** from the row "tenantId" in the result. Please note **if your tenant id is not defined, one possibility is that you are using a personal account to log in to your Azure subscription. See section 2.1.2 Configure Azure CLI on how to fix this**.

Sample output:
```
[
  {
    "id": "4be8920b-2978-43d7-ab14-04d8549c1d05",
    "name": "Sample Subscription1",
    "user": {
      "name": "Sample Account1",
      "type": "user"
    },
    "tenantId": "72f988bf-86f1-41af-91ab-2d7cd011db47",
    "state": "Enabled",
    "isDefault": true,
    "registeredProviders": [],
    "environmentName": "AzureCloud"
  },
  {
    "id": "c4528d9e-c99a-48bb-b12d-fde2176a43b8",
    "name": "Sample Subscription2",
    "user": {
      "name": "Sample Account2",
      "type": "user"
    },
    "tenantId": "72f988bf-86f1-41af-91ab-2d7cd011db47",
    "state": "Enabled",
    "isDefault": false,
    "registeredProviders": [],
    "environmentName": "AzureCloud"
  }
]
```

If you have multiple subscriptions, use below command to set the particular subscription to default which you used for your service principal in above steps.

	azure account set <SUBSCRIPTION-ID>

Example:

	azure account set 4be8920b-2178-43d7-ab14-04d8e49c1d05

Sample output:

	info:    Executing command account set
	info:    Setting subscription to "Sample Subscription" with id "4be8920b-2178-43d7-ab14-04d8e49c1d05".
	info:    Changes saved
	info:    account set command OK

### 2.2.2	Creating an AAD application ###

Create an AAD application with your information.

	azure ad app create --name <name> --password <password> --home-page <home-page> --identifier-uris <identifier-uris>

•	name: The display name for the application

•	password: The value for the password credential associated with the application that will be valid for one year by default. This is your **client secret**.

•	home-page: The URL to the application homepage. You can use a faked URL here.

•	identifier-uris: The comma-delimitied URIs that identify the application. You can use a faked URL here.

Example:


	azure ad app create --name "Service Principal for BOSH" --password "password" --home-page "http://BOSHAzureCPI" --identifier-uris "http://BOSHAzureCPI""


Below is a sample output you will get from the command, the "Application Id" is your **client id** you need to create the Service Principal.


	info:    Executing command ad app create
	+ Creating application Service Principal for BOSH
	data:    Application Id:          246e4af7-75b5-494a-89b5-363addb9f0fa
	data:    Application Object Id:   a4f0d442-af80-4d98-9cba-6bf1459ad1ea
	data:    Application Permissions:
	data:                             claimValue:  user_impersonation
	data:                             description:  Allow the application to access                  Service Principal for BOSH on behalf of the signed-in user.
	data:                             directAccessGrantTypes:
	data:                             displayName:  Access Service Principal for BOS                 H
	data:                             impersonationAccessGrantTypes:  impersonated=User, impersonator=Application
	data:                             isDisabled:
	data:                             origin:  Application
	data:                             permissionId:  1a1eb6d1-26ca-47de-abdb-365f545                 60e55
	data:                             resourceScopeType:  Personal
	data:                             userConsentDescription:  Allow the application                  to access Service Principal for BOSH on your behalf.



### 2.2.3	Create a Service Principal ###

	azure ad sp create <client-id>

Example:

	azure ad sp create 246e4af7-75b5-494a-89b5-363addb9f0fa

You can get **service-principal-name** from the value list of **Service Principal Names** to assign role to your service principal.

Sample output:

	info:    Executing command ad sp create
	+ Creating service principal for application 246e4af7-75b5-494a-89b5-363addb9f0fa
	data:    Object Id:               fcf68d7a-262b-42c4-8ef8-6a4856611155
	data:    Display Name:            Service Principal for BOSH
	data:    Service Principal Names:
	data:                             246e4af7-75b5-494a-89b5-363addb9f0fa
	data:                             http://BOSHAzureCPI
	info:    ad sp create command OK



###2.2.4	Assigning roles to your Service Principal ###

Now you have a Service Principal account, you need to grant this account access to proper resource use Azure CLI.

#### 2.2.4.1	Assigning Roles ####

	azure role assignment create --spn <service-principal-name> -o "Contributor" --subscription <subscription-id>

Example:

	azure role assignment create --spn "http://BOSHAzureCPI" -o "Contributor" --subscription 4be8920b-2178-43d7-ab14-04d8e49c1d05

After you create, you can use below command to verify it.

	azure role assignment list

Sample output:

	data:    AD Object:
	data:      ID:              7a3029f9-1b74-443e-8987-bed5b6f00009
	data:      Type:            ServicePrincipal
	data:      Display Name:    Service Principal for BOSH
	data:      Principal Name:
	data:    Scope:             /subscriptions/4be8920b-2178-43d7-ab14-04d8e49c1d05
	data:    Role:
	data:      Name:            Contributor
	data:      Permissions:
	data:        Actions:      *
	data:        NotActions:   Microsoft.Authorization/*/Write,Microsoft.Authorization/*/Delete


## 2.3	Create Azure Resources ##



### 2.3.1	Create Azure Resources with Azure XPLAT CLI ###


#### 2.3.1.1	Set Default Subscription ####

Ensure your default subscription is set to the one you used for your service principal. Please reference section 2.2.1.

#### 2.3.1.2	Create an Azure Resource Group ####

You will need to determine the deployment location for your group, then create the group in that data center.

	azure group create <resource-group-name> <location>


•	resource-group-name:

You will use this name for the following commands. Resource group name must uniquely identify the resource group within the subscription. It must be no longer than 80 characters long. It can contain only alphanumeric characters, dash, underscore, opening parenthesis, closing parenthesis, and period. The name cannot end with a period.

•	location:

Specifies the supported Azure location for the resource group. For more information, see [List all of the available geo-locations](http://azure.microsoft.com/en-us/regions/).

Example:

	azure group create bosh-res-group "East US"


After you execute above command, use below command to check whether the resource group is ready for next steps. You should not proceed to next step until you see “**Provisioning State**” becomes “**Succeeded**” in our output.

	azure group show <resource-group-name>

Example:

	azure group show bosh-res-group

Sample output:

	info:    Executing command group show
	+ Listing resource groups
	+ Listing resources for the group
	data:    Id:                  /subscriptions/4be8920b-2178-43d7-ab14-04d8e49c1d05/resourceGroups/bosh-res-group
	data:    Name:                bosh-res-group
	data:    Location:            eastus
	data:    Provisioning State:  Succeeded
	data:    Tags: null
	data:    Resources:  []
	data:    Permissions:
	data:      Actions: *
	data:      NotActions: Microsoft.Authorization/*/Write,Microsoft.Authorization/*/Delete
	data:
	info:    group show command OK


#### 2.3.1.3	Create an Azure Storage Account ####

##### 2.3.1.3.1	Create the Storage Account #####

	azure resource create <resource-group-name> <storage-account-name> Microsoft.Storage/storageAccounts <location> 2015-05-01-preview -p "{\"accountType\":\"<account-type>\"}"

•	storage-account-name:

A name for the storage account that is **unique within Azure**. **Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only**.

•	account-type:

Specifies whether the account supports locally-redundant storage, geo-redundant storage, zone-redundant storage, or read access geo-redundant storage. For example “Standard_LRS”.

Possible values are:

•	Standard_LRS

•	Standard_ZRS

•	Standard_GRS

•	Standard_RAGRS

•	Premium_LRS

Please note **Standard_ZRS** account cannot be changed to another account type later, and the other account types cannot be changed to **Standard_ZRS**. The same goes for **Premium_LRS** accounts. You can learn more about the type of Azure storage account from [here](http://azure.microsoft.com/en-us/pricing/details/storage/).

Example:

	azure resource create bosh-res-group xxxxx Microsoft.Storage/storageAccounts "East US" 2015-05-01-preview -p "{\"accountType\":\"Standard_LRS\"}"



After you execute above command, you need to use below command to check whether the resource group is ready for next steps. You need to wait until “**Provisioning State**” becomes “**Succeeded**”.

Notes: Even if you see error in the response when you executing above command, you still can use below command to check whether the storage account is created successfully under your subscription and your resource group.

	echo bosh-res-group | azure storage account show <storage_account_name>

Example:

	echo bosh-res-group | azure storage account show xxxxx


Sample output:

	+ Getting storage account
	data:    Name:
	data:    Url:
	data:    Type: Standard_LRS
	data:    Resource Group:
	data:    Location: East US
	data:    Provisioning State: Creating
	data:    Primary Location:
	data:    Primary Status:
	data:    Secondary Location:
	data:    Creation Time:
	info:    storage account show command OK

#### 2.3.1.4	Create a Public IP for Cloud Foundry ####

##### 2.3.1.4.1	Create the Public IP #####

	azure resource create <resource-group-name> <public-ip-name> Microsoft.Network/publicIPAddresses <location> 2015-05-01-preview -p "{\"publicIPAllocationMethod\":\"static\"}"

Example:

	azure resource create bosh-res-group public-ip-for-cf Microsoft.Network/publicIPAddresses "East US" 2015-05-01-preview -p "{\"publicIPAllocationMethod\":\"static\"}"


#### 2.3.1.4.2	Get the public IP Address ####

User below commend to get the public IP address for Cloud Foundry.

	azure resource show <resource-group-name> <public-ip-name> Microsoft.Network/publicIPAddresses 2015-05-01-preview

Example:

	azure resource show bosh-res-group public-ip-for-cf Microsoft.Network/publicIPAddresses 2015-05-01-preview


The value of **ipAddress** in the result is your **reserved IP for cloud foundry**.

Sample output:

	info:    Executing command resource show
	+ Getting resource bosh
	data:    Id:        /subscriptions/4be8920b-2178-43d7-ab14-04d8e49c1d05/resourceGroups/bosh-res-group/providers/Microsoft.Network/publicIPAddresses/public-ip-for-cf
	data:    Name:      public-ip-for-cf
	data:    Type:      Microsoft.Network/publicIPAddresses
	data:    Parent:
	data:    Location:  eastus
	data:    Tags:
	data:
	data:    Properties:
	data:    Property provisioningState Succeeded
	data:    Property resourceGuid 6d08437a-7170-431e-985a-1860045f6fc9
	data:    Property ipAddress 12.34.56.78
	data:    Property publicIPAllocationMethod Static
	data:    Property idleTimeoutInMinutes 4
	data:
	data:    Permissions:
	data:      Actions: *
	data:      NotActions: Microsoft.Authorization/*/Write,Microsoft.Authorization/*/Delete
	info:    resource show command OK


#### 2.3.1.5	Create a Virtual Network ####

Create a virtual network for your deployment.


	azure resource create <resource-group-name> <virtual-network-name> Microsoft.Network/virtualNetworks <location> 2015-05-01-preview -p "{\"addressSpace\": {\"addressPrefixes\": [\"<virtual-network-cidr>\"]},\"subnets\": [{\"name\": \"<bosh-subnet-name>\",\"properties\" : { \"addressPrefix\": \"<bosh-subnet-cidr>\"}}, {\"name\": \"<cloudfoundry-subnet-name>\",\"properties\" : { \"addressPrefix\": \"<cloudfoundry-subnet-cidr>\"}}]}"

•	virtual-network-name:

Names must start with a letter or number, and must contain only letters, numbers, or dashes. Spaces are not allowed.

•	virtual-network-cidr

The address space network mask in CIDR format for the virtual network.

•	bosh-subnet-name

The name of the subnet where VMs for BOSH will locate.

•	bosh-subnet-cidr

The subnet network mask in CIDR format for bosh subnet.

•	cloudfoundry-subnet-name

The name of bosh subnet where VMs for cloud foundry will locate.

•	cloudfoundry-subnet-cidr

The subnet network mask in CIDR format for cloud foundry.
Below command will create a virtual network with two subnets.

Subnets:

Name: BOSH, CIDR: 10.0.0.0/20. For BOSH VMs.
Name: CloudFoundry, CIDR: 10.0.16.0/20. For Cloud Foundry VMs.

Example:

	azure resource create bosh-res-group boshvnet-crp Microsoft.Network/virtualNetworks "East US" 2015-05-01-preview -p "{\"addressSpace\": {\"addressPrefixes\": [\"10.0.0.0/8\"]},\"subnets\": [{\"name\": \"BOSH\",\"properties\" : { \"addressPrefix\": \"10.0.0.0/20\"}}, {\"name\": \"CloudFoundry\",\"properties\" : { \"addressPrefix\": \"10.0.16.0/20\"}}]}"


# 3	Prepare Dev-Box #

After you configure your azure account, please create an Azure VM based on **Ubuntu Server 14.04 LTS** in your virtual network.

As a temporary limitation, **currently the dev machine should be on Azure and in the same VNET as BOSH VM and CF VMs**.

It is better to avoid to use the internal IP addresses **10.0.0.4** and **10.0.16.4 for your dev-box**; if your dev-box uses one of those two IP addresses, you need to change the IP address in example files to other IP address. And then execute below commands.



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


# 4	Deploy #


## 4.1	Deploy Bosh ##

### 4.1.1	Configure ###

1)	Update bosh.yml, replace following items with your Azure value just created above: **VNET-NAME**, **SUBNET-NAME**, **SUBSCRIPTION-ID**, **STORAGE-ACCOUNT-NAME**, **STORAGE-ACCESS-KEY**, **RESOURCE-GROUP-NAME**, **TENANT-ID**, **CLIENT-ID**, **CLIENT-SECRET** and **SSH-CERTIFICATE **properties.

2)	Copy your private key which matches your **SSH-CERTIFICATE** to your home directory, rename it to **bosh** and execute ‘**chmod 400 ~/bosh**’. You can use below commands to generate new private key and certificate for testing.

	openssl genrsa -out ~/bosh 2048
	openssl req -new -x509 -days 365 -key ~/bosh -out ~/bosh.pem
	chmod 400 ~/bosh

### 4.1.2	Deploy ###

First, optionally, use below commands to set debug level if you want to collect more logs.

	export BOSH_INIT_LOG_LEVEL='Debug'
	export BOSH_INIT_LOG_PATH='/tmp/log'

Deploy:

	bosh-init deploy bosh.yml


## 4.2	Deploy Cloud Foundry ##

### 4.2.1	Configure ###

1)	 Logon your BOSH director with below command.

	bosh target 10.0.0.4 # Username: admin, Password: admin

Get the UUID of your BOSH director with below command.

	bosh status

Copy **Director.UUID** to replace **BOSH-DIRECTOR-UUID** in the YAML file for Cloud Foundry.

Sample output:

    Config
             /home/vcap/.bosh_config

    Director
      Name       bosh
      URL        https://10.0.0.4:25555
      Version    1.0000.0 (00000000)
      User       admin
      UUID       640a7bf6-a39c-414e-83b9-d1bef9d6f701
      CPI        cpi
      dns        disabled
      compiled_package_cache disabled
      snapshots  enabled

    Deployment
     not set

2)	 You can reference the example file [cf_212.yml](http://cloudfoundry.blob.core.windows.net/misc/cf_212.yml) to replace the **BOSH-DIRECTOR-UUID**, **VNET-NAME**, **SUBNET-NAME**, **RESERVED-IP** and **SSL-CERT-AND-KEY** properties.

3)	 If you want to use your domain name, you can replace all ‘**cf.azurelovecf.com**’ in the example file. And please replace **10.0.0.100** with the IP address of your DNS server.

4)	 If you do not have a DNS server for the domain name, you can download [setup_dns.py](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/bosh-setup/setup_dns.py) and use below command to configure your dev-box as a DNS server for testing quickly.

	sudo python setup_dns.py -d cf.azurelovecf.com -i 10.0.16.4 -e <reserved-ip-for-cloud-foundry> -n <public-ip-of-dev-box>

•	reserved-ip-for-cloud-foundry:

  The reserved public IP address **RESERVED-IP** for Cloud Foundry.

•	public-ip-of-dev-box:

  The public IP address of your dev-box. If your dev-box reboots, its public IP address may change. You need to manually update it in **/etc/bind/cf.com.wan**.

### 4.2.2	Deploy  ###

1)	Upload stemcell

Get the value of **resource_pools.name[vms].stemcell.url** in the file [http://cloudfoundry.blob.core.windows.net/misc/bosh.yml.](http://cloudfoundry.blob.core.windows.net/misc/bosh.yml) use it to replace **STEMCELL-FOR-AZURE-URL** in below command:

	bosh upload stemcell STEMCELL-FOR-AZURE-URL

2)	Upload the Latest Cloud Foundry release

	bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=212

3)	Deploy

	bosh deployment YOUR_CLOUD_FOUNDRY_CONFIGURATION_YAML_FILE # cf_212.yml
	bosh deploy

# 5	Trouble Shooting #

1.	If your deployment fails because of timeout when creating VMs, you can delete your deployment and try to deploy it again.
2.	If you see below error information in the log, you can try to rerun your command.
```
	/var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:763:in `initialize': getaddrinfo: Name or service not known (SocketError)
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:763:in `open'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:763:in `block in connect'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/timeout.rb:55:in `timeout'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/timeout.rb:100:in `timeout'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:763:in `connect'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:756:in `do_start'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:745:in `start'
	from /var/vcap/packages/ruby_azure_cpi/lib/ruby/1.9.1/net/http.rb:1285:in `request'
```
