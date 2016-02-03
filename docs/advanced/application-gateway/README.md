# Integrating Application Gateway with Cloud Foundry on Azure

To enable advanced feature like SSL termination on your Cloud Foundry network, you can integrate Azure Application gateway. This document provides steps to create and configure [Azure Application Gateway](https://azure.microsoft.com/en-us/services/application-gateway/), that will be used as load balancer with SSL offloading enabled for Cloud Foundry. We also introduce how to create the application gateway with a single certificate or multiple certificates.

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
  # You will be asked to input the password for the ".pfx" certificate
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
  azure network vnet subnet create -g "MyResourceGroup" -e "myvnet" -n "ApplicationGateway" -a 10.0.1.0/24
  ```

3. Open the PowerShell command window and Log in.

  ```
  PS C:\> Login-AzureRmAccount
  PS C:\> get-AzureRmSubscription	# Get <GUID of your subscription> from the output. You may have multiple subscriptions, and please select the right one.
  PS C:\> Select-AzureRmSubscription -Subscriptionid <GUID of your subscription>
  ```

4. Download the PowerShell script [**New-AG.ps1**](./New-AG.ps1) to create the Application Gateway. Note AG supports multiple certificates, alternatively you can download this script [**New-AG-multi-certs.ps1**](./New-AG-multi-certs.ps1) for multiple certificate scenario.

5. Run the script and follow the prompts to specify the configurations.

  This script will create and configure a new Application Gateway with SSL offloading enabled. Note it may take around 15 to 30 minutes to finish.

  If the Application Gateway is created successfully, `New-AG.ps1` will output the public IP address of the AG.

  * Example of the expected inputs and outputs for a single certificate:

    ```
    Input your location (e.g. East Asia): East Asia
    Input your resource group name: binxi1109ag
    Input your application gateway name: ApplicationGateway
    Will create the application gateway ApplicationGateway in your resrouce group binxi1109ag
    Input your virtual network name [boshvnet-crp]: 
    Input your subnet name for the application gateway [ApplicationGateway]: 
    Input your public IP name[publicIP01]: 
    Input the list of router IP addresses (split by ";"): 10.0.16.12;10.0.16.22
    Input your system domain[cf.azurelovecf.com]: 
    Input the path of the certificate: D:\domain1.pfx
    Input the password of the certificate: User@111
    Removing it if the application gateway exists
    Adding the subnet for the application gateway
    Creating public IP address for front end configuration
    Creating IP configuration
    Configuring the back end IP address pool
    Configuring a probe
    Configuring pool settings
    Creating the front end IP configuration
    Configuring the front end IP port (80 and 443)
    Configuring the certificate used for SSL connection
    Configuring the instance size of the AG
    Creating the application gateway
    Succeed to create the application gateway.
    The public IP of the application gateway is: <Public IP Address of Application Gateway>
    ```

  * Example of the expected inputs and outputs for multiple certificates:

    ```
    Input your location (e.g. East Asia): East Asia
    Input your resource group name: binxi1109ag
    Input your application gateway name: ApplicationGateway
    Will create the application gateway ApplicationGateway in your resrouce group binxi1109ag
    Input your virtual network name [boshvnet-crp]: 
    Input your subnet name for the application gateway [ApplicationGateway]: 
    Input your public IP name[publicIP01]: 
    Input the list of router IP addresses (split by ";"): 10.0.16.12;10.0.16.22
    Input your system domain[cf.azurelovecf.com]: 
    Input the hostname, path and password of the certificates (Format: hostname1,path1,password1;hostname2,path2,password2;...): api.cf.azurelovecf.com,D:\domain1.pfx,Password1;game-2048.cf.azurelovecf.com,D:\A.pfx,Password1;demo.cf.azurelovecf.com,D:\B.pfx,Password2
    Removing it if the application gateway exists
    Adding the subnet for the application gateway
    Creating public IP address for front end configuration
    Creating IP configuration
    Configuring the back end IP address pool
    Configuring a probe
    Configuring pool settings
    Creating the front end IP configuration
    Configuring the front end IP port (80 and 443)
    Configuring the certificate used for SSL connection
    Configuring the instance size of the AG
    Creating the application gateway
    Succeed to create the application gateway.
    The public IP of the application gateway is: <Public IP Address of Application Gateway>
    ```

6. Configure DNS for your Cloud Foundry domain.

  * For production, you need to update the DNS configuration according to the belew sample.
  * For testing only, you can also update local host file.
    * Windows: `C:\Windows\System32\drivers\etc\hosts`
    * Linux: `/etc/hosts`

  Sample DNS entries after Application Gateway is created:

  ```
  <Public IP Address of Application Gateway>   api.<SYSTEM-DOMAIN>
  <Public IP Address of Application Gateway>   uaa.<SYSTEM-DOMAIN>
  <Public IP Address of Application Gateway>   login.<SYSTEM-DOMAIN>
  <Original Public IP Address of the Cloud Foundry instance>  loggregator.<SYSTEM-DOMAIN>
  ```

  You can find the IP addresses mentioned above on Azure Portal in your resource group. `<SYSTEM-DOMAIN>` is specified in your manifest for Cloud Foundry. For example, `cf.azurelovecf.com`.

7. Login to your Cloud Foundry: `cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation`.

  If you can login successfully, the Application Gateway is created successfully.

  For more information about how to create and configure an Application Gateway, please go to:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-ssl-arm/

  If you want to create an AG without SSL offloading, reference this:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-create-gateway-arm

<a name="known-issues" />
# 4 Known issues

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

2. Azure CLI is not supported for creating Application Gateway in ARM mode.

  The script that creates and configures Application Gateway is currently implemented in PowerShell. Once CLI is supported, we will also provide the CLI version of the script.
