# Integrating Application Gateway with Cloud Foundry

This document provides steps to create and configure [Azure Application Gateway](https://azure.microsoft.com/en-us/services/application-gateway/), that will be used as load balancer with SSL offloading enabled for Cloud Foundry. We also introduce how to create the application gateway with a single certificate or multiple certificates.

# 1 What is Azure Application Gateway

Azure Application Gateway provides application-level routing and load balancing services for your web front end, with following capabilities:
* Scalable, highly-available web application delivery
  Azure Application Gateway enable you to build a scalable and highly-available web front end in Azure. You control the size of the gateway and can scale your deployment based on your needs.
* Efficient, secure web frontend
  SSL offload lets you build a secure web front end with efficient backend servers and also streamline your certificate management.
* Close integration with Azure services
  Application Gateway allows easy integration with Azure Traffic Manager to support multi-region redirection, automatic failover, and zero-downtime maintenance. Application Gateway is also integrated with Azure Load Balancer to support scale-out and high-availability for both Internet-facing and internal-only web front ends.

# 2 Pre-requisites
* Azure Powershell (At least v1.0.2)

  Download [Azure Powershell](https://github.com/Azure/azure-powershell/releases/download/v1.0.2-December2015/azure-powershell.1.0.2.msi) and install.

* Prepare your certificates in the `.pfx` format.

  ```
  openssl genrsa -out domain.name.key 2048
  openssl req -new -x509 -days 365 -key domain.name.key -out domain.name.crt
  openssl pkcs12 -export -out domain.name.pfx -inkey domain.name.key -in domain.name.crt
  ```

* It is assumed that you have already created a basic Cloud Foundry deployment, with multiple routers specified in the manifest. In this example, we create 2 routers (10.0.16.12 and 10.0.16.22).

# 3 Configuration Steps  

1. Deploy your basic Cloud Foundry following this guidance: https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/guidance.md

  >**NOTE:** **DO NOT** remove HAProxy in your manifest, see [known issues](#known-issues) section for details.

2. Create an additional subnet for Application Gateway in the virtual network.

  ```
  azure network vnet subnet create -g <resource-group-name> -e <virtual-network-name> -n <subnet-name> -a <subnet-cidr>
  ```
  Example:
  ```
  azure network vnet subnet create -g “MyResourceGroup” -e “myvnet” -n “ApplicationGateway” -a 10.0.1.0/24
  ```

3. Open the PowerShell command window and Log in.

  ```
  PS C:\> Login-AzureRmAccount
  PS C:\> get-AzureRmSubscription	# Get <GUID of your subscription> from the output. You may have multiple subscriptions, and please select the right one.
  PS C:\> Select-AzureRmSubscription -Subscriptionid <GUID of your subscription>
  ```

4. Download the PowerShell script "New-AG.ps1".

  http://cloudfoundry.blob.core.windows.net/misc/New-AG.ps1

5. Configure the parameters in "New-AG.ps1".

  Following the instructions in the script, you need to replace the parameters with new AG name and settings from your CF manifest.

6. Run "New-AG.ps1". 

  This script will create and configure a new Application Gateway with SSL offloading enabled. Note it may take around 15 to 30 minutes to finish.

  If the Application Gateway is created successfully, `New-AG.ps1` will output the public IP address of the AG.

7. Configure DNS for your Cloud Foundry domain.

  * For production, you need to update the DNS configuration according to the belew sample.
  * For testing only, you can also update local host file instead.
    * Windows: `C:\Windows\System32\drivers\etc\hosts`
    * Linux: `/etc/hosts`

  Sample DNS entries after Application Gateway is created:

  ```
  <Public IP Address of Application Gateway>   api.cf.azurelovecf.com
  <Public IP Address of Application Gateway>   uaa.cf.azurelovecf.com
  <Public IP Address of Application Gateway>   login.cf.azurelovecf.com
  <Original Public IP Address of the Cloud Foundry instance>  loggregator.cf.azurelovecf.com
  ```

  You can find the IP addresses mentioned above on Azure Portal in your resource group. 

8. Login to your Cloud Foundry: `cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation`.

  If you can login successfully, the Application Gateway is created successfully.

  For more information about how to create and configure an Application Gateway, please go to:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-ssl-arm/

  If you want to create an AG without SSL offloading, reference this:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-create-gateway-arm

# 4 Multiple Certs

The following steps are for supporting multiple certificates in AG.

1. Download the PowerShell script "New-AG-multi-cert.ps1".

  http://cloudfoundry.blob.core.windows.net/misc/New-AG-multi-cert.ps1

2. Configure the parameters in “New-AG-multi-cert.ps1” and run it.

  You need to specify two different certs in the script.
  After the script is finished, each cert will be bound to a listener which has a different front end port (443 and 8443).

3. Configure DNS for your Cloud Foundry domain.

  * For production, you need to update the DNS configuration according to the belew sample.
  * For testing only, you can also update local host file instead.
    * Windows: `C:\Windows\System32\drivers\etc\hosts`
    * Linux: `/etc/hosts`

  Sample DNS entries after Application Gateway is created:

  ```
  <Public IP Address of Application Gateway>   api.cf.azurelovecf.com
  <Public IP Address of Application Gateway>   uaa.cf.azurelovecf.com
  <Public IP Address of Application Gateway>   login.cf.azurelovecf.com
  <Original Public IP Address of the Cloud Foundry instance>  loggregator.cf.azurelovecf.com
  ```

  You can find the IP addresses mentioned above on Azure Portal in your resource group. 

4. Login CF

  `cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation`

5. Push your APP.

  You can visit the app via different certs
  ```
  https://<YOUR-APP-NAME>.cf.azurelovecf.com:443	# cert1
  https://<YOUR-APP-NAME>.cf.azurelovecf.com:8443	# cert2
  ```

<a name="known-issues" />
# 5 Known issues

1. Application Gateway does not support Websocket.

  Steaming log in CF utilizes WebSocket for log collecting, that is currently still in preview stage for AG and cannot be integrated with CF.

  Workaround: HAProxy is installed to process the logging traffic. See the graph below:

  ```
  Other traffic < === > AG < ============== > Routers < =-=-= > Other CF Components
                                                 ^
                                                 |
  Logging traffic < ----- > HAProxy < -----------
  ```

  Hence, in the DNS record, we still use the original CF public IP address for log aggregator.

  >**NOTE:** Once WebSocket is supported by Application Gateway we will provide an updated guidance regarding removing HAProxy and re-create Application Gateway.

2. Azure CLI is not supported for creating Application Gateway.

  The script that creates and configures Application Gateway is currently implemented in PowerShell, once CLI is supported, we will also provide the CLI version of the script.
