# Deploy Cloud Foundry on Azure Stack

[Microsoft Azure Stack](https://azure.microsoft.com/en-us/overview/azure-stack/) is a hybrid cloud platform that lets you provide Azure services from your datacenter. Learn [how to deploy Azure Stack and offer services](https://docs.microsoft.com/en-us/azure/azure-stack/).

## Deploy BOSH director

You need to update the [global configurations](http://bosh.io/docs/azure-cpi.html#global), including setting the `environment` to `AzureStack` and configuring the `azure_stack` properties.

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

  Azure Stack uses either Azure Active Directory (AzureAD), Azure China Cloud Active Directory (AzureChinaCloudAD) or Active Directory Federation Services (AD FS) as an identity provider.

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

  If the Azure Stack is deployed with a trusted certificate, then there is no need to specify the CA Root Certificate. If you use a self-signed root certificate when deploying Azure Stack, you need to specify the cert so that CPI can verify and establish the https connection with Azure Stack endpoints. You need to specify the `ca_cert` in the global configuration.

  ```
  azure:
    azure_stack:
      ca_cert: |-
        -----BEGIN CERTIFICATE-----
        MII...
        -----END CERTIFICATE-----
  ```

  How to get the CA root certificate:

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
