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

* Prepare your certificates in the `.pfx` format.

  ```
  openssl genrsa -out domain.name.key 2048
  openssl req -new -x509 -days 365 -key domain.name.key -out domain.name.crt
  openssl pkcs12 -export -out domain.name.pfx -inkey domain.name.key -in domain.name.crt
  # You will be asked to input the password for the ".pfx" certificate
  ```

* It is assumed that you have already created a basic Cloud Foundry deployment, with multiple routers specified in the manifest, and removed HA Proxy part.
  
# 3 Configuration Steps  

## 3.1 Create Application Gateway and its Public IP

### 3.1.1 Via ARM templates (**RECOMMENDED**)

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcloudfoundry-incubator%2Fbosh-azure-cpi-release%2Fmaster%2Fdocs%2Fadvanced%2Fapplication-gateway%2Ftemplates%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

  * The cert data is the .pfx file you created in pre-requisites in base64. And you can get it by running:
  
  ```
  base64 domain.name.pfx | tr -d '\n'
  ```

### 3.1.2 Manually

* [Azure CLI](./cli/create-ag.sh)
* [Powershell](./powershell/)

## 3.2 Add Cloud Foundry routers into Application Gateway's backend pool

### 3.2.1 Update Cloud Foundry manifest

  Add `application_gateway` to the corresponding `cloud_properties` of routers in `resource_pools`:

  ```
  - cloud_properties:
      instance_type: Standard_F1
      application_gateway: <application-gateway-name>
    env:
      bosh:
        password: *********************************************************************************************************
    name: router_z1
    network: cf1
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
  ```

### 3.2.2 Update Cloud Foundry deployment

  ```
  bosh deployment multiple-vm-cf.yml
  bosh deploy -n
  ```
    
## 3.3 Configure DNS for your Cloud Foundry domain.

  * For production, you need to update the DNS configuration according to the belew sample.
  * For testing only, you can also update local host file.
    * Windows: `C:\Windows\System32\drivers\etc\hosts`
    * Linux: `/etc/hosts`

  Sample DNS entries after Application Gateway is created:

  ```
  <Public IP Address of Application Gateway>   <SYSTEM-DOMAIN>
  ```

  You can find the IP addresses mentioned above on Azure Portal in your resource group. `<SYSTEM-DOMAIN>` is specified in your manifest for Cloud Foundry.

# 4 Login to your Cloud Foundry
  
  `cf login -a https://api.<SYSTEM-DOMAIN> --skip-ssl-validation`.

  If you can login successfully, the Application Gateway is created successfully.

  For more information about how to create and configure an Application Gateway, please go to:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-ssl-arm/

  If you want to create an AG without SSL offloading, reference this:
  https://azure.microsoft.com/en-us/documentation/articles/application-gateway-create-gateway-arm

