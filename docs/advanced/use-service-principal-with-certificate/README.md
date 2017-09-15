# Use Service Principal with certificate

CPI v35+ supports service principal with password (`tenant_id`, `client_id` and `client_secret`) or certificate (`tenant_id`, `client_id` and `certificate`).

## AzureAD authentication

1. You can create service principal with certificate using [Azure CLI 1.0](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal-cli#create-service-principal-with-certificate) or [Powershell](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal#create-service-principal-with-self-signed-certificate). Azure CLI 2 doesn't support the creation of certificate-based authentication credentials.

1. After the above steps, you will get a certificate named `examplecert.pem`. You need to add `certificate` and remove `client_secret` in the [global configurations](https://bosh.io/docs/azure-cpi.html#global).

    ```
    client_id: <YOUR-CLIENT-ID>
    certificate: |-
      -----BEGIN PRIVATE KEY-----
      MII...
      -----END PRIVATE KEY-----
      -----BEGIN CERTIFICATE-----
      MII...
      -----END CERTIFICATE-----
    ```

    Example ops file: [use-certificate-based-service-principal-AzureAD.yml](./use-certificate-based-service-principal-AzureAD.yml).

## ADFS authentication in Azure Stack

1. You can [create service principal with certificate for ADFS](https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-create-service-principals#create-service-principal-for-ad-fs). Please note down the service principal name.

1. You need to export the certificate with the Microsoft Management Console (MMC) Snap-in.

    1. Open a Command Prompt window.

    1. Type `mmc` and press the ENTER key.

    1. On the `File` menu, click `Add/Remove Snap In`.

    1. Click `Add`.

    1. In the `Add Standalone Snap-in` dialog box, select `Certificates`.

    1. Click `Add`.

    1. In the `Certificates snap-in` dialog box, select `My user account` and click `Finish`.

    1. On the Add/Remove Snap-in dialog box, click OK.

    1. In the `Console Root` window, click `Certificates - Current User`, `Personal`, `Certificates` to view the certificate list.

    1. Click the certificate whose name is your service principal name. Righ-click it, and select `All Tasks`, `Export`.

    1. Follow the `Certificate Export Wizard`, export the private key, select the `.PFX` format including all certificates, specify the password and the file name (e.g. `CPI.pfx`), and export it.

1. Convert the `.PFX` format to `.PEM` format.

    ```
    openssl pkcs12 -in CPI.pfx -out CPI.pem -nodes
    ```

    Remove the extra attributes, and keep only the private key and certificate.

1. You need to add `certificate` and remove `client_secret` in the [global configurations](https://bosh.io/docs/azure-cpi.html#global), and set they authentication to `ADFS` for Azure Stack.

    ```
    client_id: <YOUR-CLIENT-ID>
    certificate: |-
      -----BEGIN PRIVATE KEY-----
      MII...
      -----END PRIVATE KEY-----
      -----BEGIN CERTIFICATE-----
      MII...
      -----END CERTIFICATE-----
    azure_stack:
      authentication: ADFS
    ```

    Example ops file: [use-certificate-based-service-principal-ADFS.yml](./use-certificate-based-service-principal-ADFS.yml).
