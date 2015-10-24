# Guide to Deploy Cloud Foundry on Azure with template #

# Overview #

This documents describes the steps to create Cloud Foundry on Azure environment using Azure resource template, which involves setting up a Bosh VM and using it to provision Cloud Foundry in Azure. If you want to deploy your environment step by step, you can reference [the Step by Step Manual Guide](https://github.com/Azure/bosh-azure-cpi-release/blob/master/docs/guide.md).


# Updates from last version #


Following are updates from [Preview version of Cloud Foundry on Azure](http://azure.microsoft.com/blog/2015/05/29/try-cloud-foundry-on-azure-today/).

•	Update Azure CPI code to pick up version 2972 from Cloud Foundry main branch

•	Support [bosh-init](https://github.com/cloudfoundry/bosh-init)

•	Support creating multiple Cloud Foundry VMs

•	Support [Bosh snapshot](https://bosh.io/docs/snapshots.html)

•	Remove NodeJS code and related dependencies, keeping all Azure CPI code Ruby based

# Prerequisites #

•	Create an Azure account

•	Install and Configure Azure CLI

# 1	Prepare an Azure Environment #

Setting up Cloud Foundry in Azure involves the following steps:

•	Prepare your Azure Account

•	Setup and configure a dev machine using Azure Template

•	Deploy Bosh

•	Deploy Cloud Foundry



## 1.1	Prepare your Azure Account ##

To configure your Azure account for BOSH and Cloud Foundry:

1.	Prepare Azure CLI

2.	Create a Service Principal

## 1.2	Prepare Azure CLI ##

1.2.1	Install Azure CLI

Install and configure Azure CLI following the documentation [here](http://azure.microsoft.com/en-us/documentation/articles/xplat-cli/). If you are using Windows, make sure you use **command line** but not PowerShell to run the Azure CLI. It is suggested you run the CLI commands here using Ubuntu Server 14.04 LTS or Windows 8.1.

### 1.2.2	Configure Azure CLI ###


#### 1.2.2.1	Set mode to Azure Resource Management ####

	azure config mode arm

#### 1.2.2.2	Login ####

Please note this login method requires a work or school account.

If you do not currently have a work or school account, and are using a personal account to log in to your Azure subscription, you can easily create a work or school account, following this [guide](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-connect/).

If you have enabled MFA, creating the service principal may fail. You need to disable MFA and try again.

	#Enter your Microsoft account credentials when prompted.
	azure login

## 1.3	Create a Service Principal ##

Azure CPI provisions resources in Azure using the Azure Resource Manager (ARM) APIs. We use a Service Principal account to give Azure CPI the access to proper resources.


### 1.3.1	Set Default Subscription ###

Ensure your default subscription is set to the one you want to create your service principal.

First check whether you have multiple subscriptions:

	azure account list --json

Below is a sample output from the command.

You can get **SUBSCRIPTION-ID** from the row "id" in the result.

You can get **TENANT-ID** from the row "tenantId" in the result. Please note **if your tenant id is not defined, one possibility is that you are using a personal account to log in to your Azure subscription. See section 1.2.2 Configure Azure CLI on how to fix this**.

Sample output:
```
[
  {
    "id": "4be8920b-2978-43d7-ab14-04d8549c1d05",
    "name": "Sample Subscription",
    "user": {
      "name": "Sample Account",
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
    "name": "Sample Subscription1",
    "user": {
      "name": "Sample Account1",
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

### 1.3.2	Creating an AAD application ###

Create an AAD application with your information.

	azure ad app create --name <name> --password <password> --home-page <home-page> --identifier-uris <identifier-uris>

•	name: The display name for the application

•	password: The value for the password credential associated with the application that will be valid for one year by default. This is your **CLIENT-SECRET**.

•	home-page: The URL to the application homepage. You can use a faked URL here.

•	Identifier-uris: The comma-delimitied URIs that identify the application. You can use a faked URL here.

Example:

	azure ad app create --name "Service Principal for BOSH" --password "password" --home-page "http://BOSHAzureCPI" --identifier-uris "http://BOSHAzureCPI"

Below is a sample output you will get from the command, the "Application Id" is your **CLIENT-ID** you need to create the Service Principal.

	info:    Executing command ad app create
	+ Creating application Service Principal for BOSH
	data:    Application Id:          246e4af7-75b5-494a-89b5-363addb9f0fa
	data:    Application Object Id:   a4f0d442-af80-4d98-9cba-6bf1459ad1ea
	data:    Application Permissions:
	data:                             claimValue:  user_impersonation
	data:                             description:  Allow the application to access Service Principal for BOSH on behalf of the signed-in user.
	data:                             directAccessGrantTypes:
	data:                             displayName:  Access Service Principal for BOSH
	data:                             impersonationAccessGrantTypes:  impersonated=User, impersonator=Application
	data:                             isDisabled:
	data:                             origin:  Application
	data:                             permissionId:  1a1eb6d1-26ca-47de-abdb-365f54560e55
	data:                             resourceScopeType:  Personal
	data:                             userConsentDescription:  Allow the applicationto access Service Principal for BOSH on your behalf.
	data:                             userConsentDisplayName:  Access Service Principal for BOSH
	data:                             lang:
	info:    ad app create command OK

### 1.3.3	Create a Service Principal ###

	azure ad sp create <CLIENT-ID>

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

### 1.3.4	Assigning roles to your Service Principal ###

Now you have a Service Principal account, you need to grant this account access to proper resource use Azure CLI.

#### 1.3.4.1	Assigning Roles ####

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

# 2	Setup and configure a dev machine using Azure Template #

Here we’ll create the following Azure resources that’s required for running Cloud Foundry:

•	An Azure Storage Account

•	Two reserved IPs

•	A Virtual Network

•	A Virtual Machine with a public IP

These resources can be setup by manual operations, and you can refer to [the manual guide](https://github.com/Azure/bosh-azure-cpi-release/blob/master/docs/guide.md). Another way is to deploy an [Azure Template](https://azure.microsoft.com/en-us/documentation/articles/resource-group-authoring-templates/) with Azure Resource Manager. The template (in JSON format) will provide a declarative way to define deployment.

Click the button “Deploy to Azure” [here](https://github.com/Azure/azure-quickstart-templates/tree/master/bosh-setup) to provision the resources above in Azure.
The template expects the following parameters:


<table><tr><td>Name</td><td>Description</td></tr><tr><td>location</td><td>location where the resources will be deployed</td></tr><tr><td>newStorageAccountName</td><td><b>Unique DNS Name</b> for the Storage Account where the Virtual Machine's disks will be placed. <br/><b>It can contain only lowercase letters and numbers. It has to be between 3 and 24 characters.</b></td></tr><tr><td>virtualNetworkName</td><td>name of the virtual network</td></tr><tr><td>subnetNameForBosh</td><td>name of the subnet for Bosh</td></tr><tr><td>subnetNameForCloudFoundry</td><td>name of the subnet for CloudFoundy</td></tr><tr><td>vmName</td><td>Name of Virtual Machine</td></tr><tr><td>vmSize</td><td>Size of the Virtual Machine</td></tr><tr><td>adminUsername</td><td>Username for the Virtual Machines</td></tr><tr><td>adminPassword</td><td>Password for the Virtual Machine</td></tr><tr><td>enableDNSOnDevbox</td><td>A default DNS will be setup in the dev-box if it is true. <br/><b>If you enable it, you should reboot the dev-box manually after you logon to dev-box at the first time. If the dev-box reboots, its public IP address may change. You need to manually update it in /etc/bind/cf.com.wan.</b></td></tr></table>


After filling in all parameters, you can click the button “Deploy to Azure” to start the provision.
You can check ~/install.log to determine the status of the deployment. When the deployment succeeds you will find **Finish** at the end of the log file.

Notes:

1)	 Currently BOSH can be only deployed from a Virtual Machine in the same VNET on Azure.

2)	 The default type of Azue storage account is "Standard_LRS" (Locally Redundant Storage). For a list of available Azure storage accounts, their capacities and prices, check [here](http://azure.microsoft.com/en-us/pricing/details/storage/). Please note Standard_ZRS account cannot be changed to another account type later, and the other account types cannot be changed to Standard_ZRS. The same goes for Premium_LRS accounts.


# 3	Deploy #

## 3.1	Deploy Bosh ##

### 3.1.1	Configure ###

The Azure template pre-creates the deployment manifest file bosh.yml in your home directory.

Update the template bosh.yml to replace the **TENANT-ID**, **CLIENT-ID**, **CLIENT-SECRET** properties. The **TENANT-ID**, **CLIENT-ID**, **CLIENT-SECRET** are created in step 1.3 Creating a Service Principal above.


### 3.1.2	Deploy ###

Run the following commands in your home directory to deploy bosh:

	./deploy_bosh.sh

More verbose logs are written to ~/run.log.


## 3.2	Deploy Cloud Foundry ##


### 3.2.1	Configure ###


1)	 Logon your BOSH director with below command.

	bosh target 10.0.0.4 # Username: admin, Password: admin

Get the UUID of your BOSH director with below command.

	bosh status

Copy **Director.UUID** to replace **BOSH-DIRECTOR-UUID** in the YAML file for cloud foundry.

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

2)	 You can reference the example file [cf_212.yml](http://cloudfoundry.blob.core.windows.net/misc/cf_212.yml) to replace the **BOSH-DIRECTOR-UUID**, **VNET-NAME**, **SUBNET-NAME**, **RESERVED-IP** and **SSL-CERT-AND-KEY** properties. The BOSH-DIRECTOR-UUID, VNET-NAME and SUBNET-NAME are created in step 2. The RESERVED-IP can be found in the row "cf-ip" in /home/YOUR-USERNAME/settings. To replace the SSL-CERT-AND-KEY, you need to concatenate the cert in /home/YOUR-USERNAME/bosh.yml and the key in /home/YOUR-USERNAME/bosh.

3)	 If you set enableDNSOnDevbox true, the dev box can serve as a DNS and it has been pre-configured in cf_212.yml. **You must reboot your dev box before deploying cloud foundry**.

4)	 If you want to use your domain name, you can replace all ‘**cf.azurelovecf.com**’ in the example file. And please replace **10.0.0.100** with the IP address of your DNS server.

### 3.2.2	Deploy  ###

1)	Upload stemcell

Get the value of **resource_pools.name[vms].stemcell.url** in the file [http://cloudfoundry.blob.core.windows.net/misc/bosh.yml](http://cloudfoundry.blob.core.windows.net/misc/bosh.yml) , use it to replace **STEMCELL-FOR-AZURE-URL** in below command:

	bosh upload stemcell STEMCELL-FOR-AZURE-URL

2)	Upload the Latest Cloud Foundry release

	bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=212

3)	Deploy

	bosh deployment YOUR_CLOUD_FOUNDRY_CONFIGURATION_YAML_FILE # cf_212.yml
	bosh deploy

# 4	Trouble Shooting #

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
