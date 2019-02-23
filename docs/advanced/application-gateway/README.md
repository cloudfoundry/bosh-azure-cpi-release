# Integrating Application Gateway with CF on Azure

This document provides steps to create [Azure Application Gateway](https://azure.microsoft.com/services/application-gateway/), and integrate it as load balancer for Cloud Foundry. 

## Azure Application Gateway background

Microsoft Azure Application Gateway is a dedicated virtual appliance, providing application delivery controller (ADC) as a service. It offers various layer 7 load balancing capabilities, supports SSL offloading and end to end SSL, Web Application Firewall, cookie-based session affinity, url path-based routing, multi site hosting, and others. For a full list of supported features, see [Introduction to Application Gateway](https://docs.microsoft.com/azure/application-gateway/application-gateway-introduction)


## Pre-requisites

* Follow the [guidance](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) to setup a Cloud Foundry deployment

* Prepare your certificates in the `.pfx` format

  ```
  openssl genrsa -out domain.name.key 2048
  openssl req -new -x509 -days 365 -key domain.name.key -out domain.name.crt
  openssl pkcs12 -export -out domain.name.pfx -inkey domain.name.key -in domain.name.crt
  # You will be asked to input the password for the ".pfx" certificate
  ```

## Configure the CF deployment for Application Gateway

### 1. Create Application Gateway 

To create the application gateway, you need to create a public IP and a subnet, then you can enable/configure the optional features, like SSL offloading. You can complete these steps through ARM template or scripts. This applies to both new and updating deployments.

#### Creating with ARM templates (**RECOMMENDED**)

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcloudfoundry-incubator%2Fbosh-azure-cpi-release%2Fmaster%2Fdocs%2Fadvanced%2Fapplication-gateway%2Ftemplates%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

* The cert data is the .pfx file you created in pre-requisites in base64. And you can get it by running:

```
base64 domain.name.pfx | tr -d '\n'
```

#### Creating manually with scripts

* [Azure CLI](./cli/create-ag.sh)
* [Powershell](./powershell/)

### 2 Associate Application Gateway and Cloud Foundry routers

#### Update Cloud Foundry manifest

Update the cloud config from

```
- name: cf-router-network-properties
  cloud_properties:
    load_balancer: ((load_balancer_name))
```

to

```
- name: cf-router-network-properties
  cloud_properties:
    application_gateway: ((application_gateway_name))
```

#### Update Cloud Foundry deployment

Remove `load_balancer_name` and specify `application_gateway_name` in `deploy_cloud_foundry.sh`, and run the script.

```
./deploy_cloud_foundry.sh
```
    
### 3. Configure DNS for your Cloud Foundry domain

Update the DNS entries, so the Application gateway's IP is associated with CF system domain.

* For testing only, you can also update local host file.

    * Windows: `C:\Windows\System32\drivers\etc\hosts`

    * Linux: `/etc/hosts`

* Below is a sample DNS entry after Application Gateway is created:

    ```
    <Public IP Address of Application Gateway>   <SYSTEM-DOMAIN>
    ```

    You can find the IP addresses mentioned above on Azure Portal in your resource group. `<SYSTEM-DOMAIN>` is specified in your manifest for Cloud Foundry.

### 4. Log into CF deployment for validating
  
`cf login -a https://api.<SYSTEM-DOMAIN> --skip-ssl-validation`.

If you can login successfully, the Application Gateway is created successfully.

For more information about how to create and configure an Application Gateway, please go to:
https://azure.microsoft.com/en-us/documentation/articles/application-gateway-ssl-arm/

If you want to create an AG without SSL offloading, reference this:
https://azure.microsoft.com/en-us/documentation/articles/application-gateway-create-gateway-arm
