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

  If a self-signed root certificate is used when deploying Azure Stack, you **MUST** specify the `ca_cert` in the global configuration to make CPI trust the Azure Stack CA root certificate.

  ```
  azure:
    azure_stack:
      ca_cert: |-
        -----BEGIN CERTIFICATE-----
        MII...
        -----END CERTIFICATE-----
  ```

## Deploy Cloud Foundry

Deploying Cloud Foundry on Azure Stack is basically same with the deployment on Azure.

If you would like to replace local WebDAV blobstore with external Azure Stack Storage blobstore via [fog](https://github.com/fog/fog-azure-rm), you can use the ops file [use-azure-stack-storage-blobstore.yml](./use-azure-stack-storage-blobstore.yml), which introduces the following new variables for Azure Stack storage connection information and container names.

Variable examples of `use-azure-stack-storage-blobstore.yml` are:

```
environment: AzureStack
blobstore_storage_account_name: <your-storage-account-name>
blobstore_storage_access_key: <your-storage-account-access-key>
blobstore_storage_dns_suffix: <your-storage-account-dns-suffix>
app_package_directory_key: example-apps-dir
buildpack_directory_key: example-buildpacks-dir
droplet_directory_key: example-droplets-dir
resource_directory_key: example-resources-dir
```

`<your-storage-account-dns-suffix>` is the dns suffix of your storage account. For example, `local.azurestack.external` for Azure Stack Development Kit, and `<location>.<azure_stack_domain>` for Azure Stack integrated systems.

If a self-signed root certificate is used when deploying Azure Stack, you **MUST** specify the `trusted_certs` in the [director configuration](https://bosh.io/docs/trusted-certs/) to make the API VM (Cloud Controller) trust the Azure Stack CA root certificate.
