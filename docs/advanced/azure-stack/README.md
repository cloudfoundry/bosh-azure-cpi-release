# Deploy Cloud Foundry on Azure Stack

[Microsoft Azure Stack](https://azure.microsoft.com/en-us/overview/azure-stack/) is a hybrid cloud platform that lets you provide Azure services from your datacenter. Learn [how to deploy Azure Stack and offer services](https://docs.microsoft.com/en-us/azure/azure-stack/).

## Pre-requisites

  If the Azure Stack is deployed with a trusted certificate, then there is no need to specify the CA Root Certificate and you can skip the section.

  If a self-signed root certificate is used when deploying Azure Stack, you need to specify the certificate so that the https connection to Azure Stack endpoints can be verified.

  Three options to get the CA root certificate:

  * Option 1: Get the CA root certificate from the Azure Stack operator. It's recommended.

  * Option 2: Follow the [doc](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#trust-the-azure-stack-ca-root-certificate) to get the `/var/lib/waagent/Certificates.pem`, which is the CA root certificate.

  * Option 3: Run the following Powershell script to export the CA root certificate in PEM format. See more in [Export the Azure Stack CA root certificate](https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-cli-admin#export-the-azure-stack-ca-root-certificate).

    ```
    $label = "AzureStackSelfSignedRootCert"
    Write-Host "Getting certificate from the current user trusted store with subject CN=$label"
    $root = Get-ChildItem Cert:\CurrentUser\Root | Where-Object Subject -eq "CN=$label" | select -First 1
    if (-not $root)
    {
        Log-Error "Cerficate with subject CN=$label not found"
        return
    }

    Write-Host "Exporting certificate"
    Export-Certificate -Type CERT -FilePath root.cer -Cert $root

    Write-Host "Converting certificate to PEM format"
    certutil -encode root.cer root.pem
    ```

## [CPI Global Configurations](http://bosh.io/docs/azure-cpi.html#global) for Azure Stack

### Environment

You need to set the `environment` to `AzureStack`. The Ops file [custom-environment.yml](https://github.com/cloudfoundry/bosh-deployment/blob/master/azure/custom-environment.yml) can be used.

```
azure:
  environment: AzureStack
```

### Azure Stack Properties

* Domain

  For Azure Stack development kit, this value is set to `local.azurestack.external`. To get this value for Azure Stack integrated systems, contact your service provider.

  ```
  azure:
    azure_stack:
      domain: ((azure_stack_domain))
  ```

* Management Endpoint Prefix

  ```
  azure:
    azure_stack:
      endpoint_prefix: management
  ```

  The prefix is for the resource manager url (`https://<endpoint_prefix>.<azure_stack_domain>`). The default value is `management`.

* Active Directory Service Endpoint Resource ID

  ```
  azure:
    azure_stack:
      resource: ((azure_stack_ad_service_endpoint_resource_id))
  ```

  Two options to get the resource ID:

  * `curl https://<endpoint_prefix>.<azure_stack_domain>/metadata/endpoints?api-version=1.0 -s | jq ".authentication.audiences[0]" -r`

  * `Get-AzureRmEnvironment "<YOUR-ENVIRONMENT-NAME>" | Select-Object -ExpandProperty ActiveDirectoryServiceEndpointResourceId`

* Authentication

  Three [identity provider](https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-identity-overview) are supported: Azure Active Directory (AzureAD), Azure China Cloud Active Directory (AzureChinaCloudAD) and Active Directory Federation Services (AD FS).

  * Azure Active Directory

    Please specify the authentication to `AzureAD`, and provide the service principal with password (`tenant_id`, `client_id` and `client_secret`).

    ```
    azure:
      tenant_id: <TENANT-ID>
      client_id: <CLIENT-ID>
      client_secret: <CLIENT-SECRET>
      azure_stack:
        authentication: AzureAD
    ```

  * Azure China Cloud Active Directory

    Please specify the authentication to `AzureChinaCloudAD`, and provide the service principal with password (`tenant_id`, `client_id` and `client_secret`).

    ```
    azure:
      tenant_id: <TENANT-ID>
      client_id: <CLIENT-ID>
      client_secret: <CLIENT-SECRET>
      azure_stack:
        authentication: AzureChinaCloudAD
    ```

  * Active Directory Federation Services

    Please specify the authentication to `ADFS`, and provide the [service principal with certificate](../use-service-principal-with-certificate/) (`tenant_id`, `client_id` and `certificate`).

    ```
    azure:
      environment: AzureStack
      tenant_id: <TENANT-ID>
      client_id: <CLIENT-ID>
      certificate: <CERTIFICATE>
      azure_stack:
        authentication: ADFS
    ```

* CA Root Certificate

  If a self-signed root certificate is used when deploying Azure Stack, you **MUST** specify the `ca_cert` in the global configuration to make CPI trust the Azure Stack CA root certificate. Check the section `Pre-requisite` to get the certificate.

  ```
  azure:
    azure_stack:
      ca_cert: |-
        -----BEGIN CERTIFICATE-----
        MII...
        -----END CERTIFICATE-----
  ```

## Deploy via bosh-setup template

You can [deploy CF via bosh-setup templates](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md). Here's a sample Powershell script to deploy the template in ASDK. Before running it, you need to download [AzureStack-Tools](https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-powershell-download). You can also use Azure CLI or Azure Portal to deploy it.

```
Set-StrictMode -Version 2.0
Clear-Host

Import-Module C:\AzureStack-Tools-master\Connect\AzureStack.Connect.psm1

$myLocation = "local"
$azureStackDomain = "local.azurestack.external" # If you are using Azure Stack integrated systems, contact your service provider to get the domain.
$tenantArmEndPoint = "https://management." + $azureStackDomain + "/"

###########
# CONNECT #
###########

Add-AzureRMEnvironment -Name "AzureStackUser" -ARMEndpoint $tenantArmEndPoint
# Get Azure Stack Environment Information
$env = Get-AzureRmEnvironment 'AzureStackUser'

$AadTenantId = "<your-tenant-id>"
$clientID     = "<your-client-id>"
$clientSecret = ("<your-client-secret>" | ConvertTo-SecureString -AsPlainText -Force)
$credential = New-Object System.Management.Automation.PSCredential($clientID,$clientSecret)
Add-AzureRmAccount -Environment $env -Credential $credential -TenantId $AadTenantId -ServicePrincipal -Verbose

# Get Azure Stack Environment Subscription
Get-AzureRmSubscription -SubscriptionName "<your-subscription-name>" | Select-AzureRmSubscription

##########
# DEPLOY #
##########

# Set Deployment Variables
$myNum = "{0:000}" -f (Get-Random -Minimum 1 -Maximum 999)
$RGName = "bosh$myNum"

# Create Resource Group for Template Deployment
New-AzureRMResourceGroup -Name ($RGName + "RG") -Location $myLocation -Force -Verbose

# Deploy Simple IaaS Template 
$rgDeploymentResult = New-AzureRmResourceGroupDeployment `
    -Name ($RGName + "Deployment") `
    -ResourceGroupName ($RGName + "RG") `
    -TemplateUri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/bosh-setup/azuredeploy.json" `
    -vmName ($RGName + "VM") `
    -ubuntuOSVersion "16.04-LTS" `
    -adminUsername "<your-admin-username>" `
    -sshKeyData "<your-ssh-public-key>" `
    -environment "AzureStack" `
    -tenantID $AadTenantId `
    -clientID $clientID `
    -clientSecret $clientSecret `
    -loadBalancerSku "basic" `
    -autoDeployBosh "disabled" `
    -autoDeployCloudFoundry "disabled" `
    -azureStackDomain $azureStackDomain `
    -azureStackResource (Get-AzureRmEnvironment "AzureStackUser" | Select-Object -ExpandProperty ActiveDirectoryServiceEndpointResourceId) `
    -Verbose -Force
```

Note:

1. The Ubuntu OS version is based on which version is uploaded to your Azure Stack.

1. The Standard SKU load balancer is not supported in Azure Stack, so the `loadBalancerSku` has to be `basic`.

1. You can enable `autoDeployBosh` and `autoDeployCloudFoundry`. If enabled, you can skip the next two sections.

## Deploy BOSH director

You need to update the [CPI global configurations](http://bosh.io/docs/azure-cpi.html#global), including setting the `environment` to `AzureStack` and configuring the `azure_stack` properties.

Run `./deploy_bosh.sh` and export the following environment variables from `~/login_bosh.sh` into `~/.profile`.

```
export BOSH_ENVIRONMENT=10.0.0.4
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET="\$(bosh int ~/bosh-deployment-vars.yml --path /admin_password)"
export BOSH_CA_CERT="\$(bosh int ~/bosh-deployment-vars.yml --path /director_ssl/ca)"
```

## Deploy Cloud Foundry

Deploying Cloud Foundry on Azure Stack is basically same with the deployment on Azure. Run `./deploy_cloud_foundry.sh`.

### Use Azure Stack Storage as Cloud Foundry Blobstore

[CAPI 1.67.0](https://github.com/cloudfoundry/capi-release/releases/tag/1.67.0) supports Azure Stack Storage as its blobstore via [fog](https://github.com/fog/fog-azure-rm). [cf-deployment v4.0.0](https://github.com/cloudfoundry/cf-deployment/releases/tag/v4.0.0) has upgraded CAPI release to v1.67.0. By default, the bosh-setup template has adopted cf-deployment v4.0.0. If you are using the template, you can skip this section.

If you are not using the template, you need to do the following things:

1.  If a self-signed root certificate is used when deploying Azure Stack, you **MUST** specify the `trusted_certs` in the [director configuration](https://bosh.io/docs/trusted-certs/) to make the API VM (Cloud Controller) trust the Azure Stack CA root certificate.

1. Add the key `azure_storage_dns_suffix` into the configuration `fog_connection` of the ops file [use-azure-storage-blobstore.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/use-azure-storage-blobstore.yml). The value should be the dns suffix of your storage account. For example, `local.azurestack.external` for Azure Stack Development Kit, and `<location>.<azure_stack_domain>` for Azure Stack integrated systems.
