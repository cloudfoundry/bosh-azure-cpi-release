# Deploy Cloud Foundry on Azure Stack

[Microsoft Azure Stack](https://azure.microsoft.com/en-us/overview/azure-stack/) is a hybrid cloud platform that lets you provide Azure services from your datacenter. Learn [how to deploy Azure Stack and offer services](https://docs.microsoft.com/en-us/azure/azure-stack/).

Before deploying the BOSH director, you need to update the [global configurations](http://bosh.io/docs/azure-cpi.html#global), including setting the `environment` to `AzureStack` and configuring the `azure_stack` properties.

## Environment

You need to set the `environment` to `AzureStack`. The Ops file [custom-environment.yml](https://github.com/cloudfoundry/bosh-deployment/blob/master/azure/custom-environment.yml) can be used.

```
azure:
  environment: AzureStack
```

## Azure Stack Properties

* Domain

  For Azure Stack development kit, this value is set to `local.azurestack.external`. To get this value for Azure Stack integrated systems, contact your service provider.

  ```
  azure:
    azure_stack:
      domain: ((azure_stack_domain))
  ```

* Active Directory Service Endpoint Resource ID

  ```
  azure:
    azure_stack:
      resource: ((azure_stack_ad_service_endpoint_resource_id))
  ```

  You can get the resource ID using the Powershell script:

  ```
  Get-AzureRmEnvironment "<YOUR-ENVIRONMENT-NAME>" | Select-Object -ExpandProperty ActiveDirectoryServiceEndpointResourceId
  ```

* Management Endpoint Prefix

  ```
  azure:
    azure_stack:
      endpoint_prefix: management
  ```

  The prefix is for the resource manager url (`https://<endpoint_prefix>.<azure_stack_domain>`). The default value is `management`.

* Authentication

  Azure Stack uses either Azure Active Directory (AzureAD) or Active Directory Federation Services (AD FS) as an identity provider. For Azure CPI, only `AzureAD` is supported.

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

* CA Cert

  If you use a self-signed root certificate when deploying Azure Stack, you need to specify the cert so that CPI can verify and establish the https connection with Azure Stack endpoints. The Azure Stack CA root certificate is available on the development kit. Sign in to your development kit and run the following Powershell script to export the Azure Stack root certificate in PEM format:

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

  Please specify the `ca_cert` in the global configuration.

  ```
  azure:
    azure_stack:
      ca_cert: |-
        -----BEGIN CERTIFICATE-----
        MII...
        -----END CERTIFICATE-----
  ```
