# Use Service Principal with certificate

CPI v35+ supports service principal with password (`tenant_id`, `client_id` and `client_secret`) or certificate (`tenant_id`, `client_id` and `certificate`).

## AzureAD authentication

1. You can create service principal with certificate using [Azure CLI](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal-cli#create-service-principal-with-certificate).

1. You will get the certificate from step 1. You need to add a new property `certificate` and remove the property `client_secret` in the [global configurations](https://bosh.io/docs/azure-cpi.html#global).

    ```diff
    client_id: <YOUR-CLIENT-ID>
    --- client_secret: <YOUR-CLIENT_SECRET>
    +++ certificate: |-
    +++   -----BEGIN PRIVATE KEY-----
    +++   MII...
    +++   -----END PRIVATE KEY-----
    +++   -----BEGIN CERTIFICATE-----
    +++   MII...
    +++   -----END CERTIFICATE-----
    ```

    Example ops file: [use-certificate-based-service-principal-AzureAD.yml](./use-certificate-based-service-principal-AzureAD.yml).
