# Create a Service Principal - Azure CLI

This topic shows you how to permit a service principal (such as an automated process, application, or service) to access other resources in your subscription.

A service principal contains the following credentials which will be mentioned in this page. Please store them in a secure location because they are sensitive credentials.

- **TENANT_ID**
- **CLIENT_ID**
- **CLIENT_SECRET** 

# 1 Prepare Azure CLI

## 1.1 Install Azure CLI

Install and configure Azure CLI following the documentation [**HERE**](http://azure.microsoft.com/en-us/documentation/articles/xplat-cli/).

>**NOTE:**
  * It is suggested to run Azure CLI using Ubuntu Server 14.04 LTS or Windows 10.
  * If you are using Windows, it is suggested that you use **command line** but not PowerShell to run Azure CLI.
  * If you hit the error `/usr/bin/env: node: No such file or directory` when running `azure` commands, you need to run `sudo ln -s /usr/bin/nodejs /usr/bin/node`.

<a name="configure_azure_cli"></a>
## 1.2 Configure Azure CLI

### 1.2.1 Set mode to Azure Resource Management

```
azure config mode arm
```

### 1.2.2 Login

```
#Enter your Microsoft account credentials when prompted.
azure login --environment $ENVIRONMENT
```

>**NOTE:**
  * `azure login` requires a work or school account. Never login with your personal account. If you do not have a work or school account currently, you can easily create a work or school account with the [**guide**](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-connect/).
  * `$ENVIRONMENT` can be `AzureCloud`, `AzureChinaCloud` and so on.
  * If you fail to login `AzureChinaCloud` with a `CERT_UNTRUSTED` error, please use the latest version of node (4.x) and mostly the issue should be resolved. [azure-xplat-cli/2725](https://github.com/Azure/azure-xplat-cli/issues/2725)

# 2 Create a Service Principal

Azure CPI provisions resources in Azure using the Azure Resource Manager (ARM) APIs. We use a Service Principal account to give Azure CPI the access to proper resources.

## 2.1 Set Default Subscription

1. Check whether you have multiple subscriptions.

  ```
  azure account list --json
  ```

  Sample Output:

  ```
  [
    {
      "id": "12345678-1234-5678-1234-678912345678",
      "name": "Sample Subscription",
      "user": {
        "name": "Sample Account",
        "type": "user"
      },
      "tenantId": "11111111-1234-5678-1234-678912345678",
      "state": "Enabled",
      "isDefault": true,
      "registeredProviders": [],
      "environmentName": "AzureCloud"
    },
    {
      "id": "87654321-1234-5678-1234-678912345678",
      "name": "Sample Subscription1",
      "user": {
        "name": "Sample Account1",
        "type": "user"
      },
      "tenantId": "22222222-1234-5678-1234-678912345678",
      "state": "Enabled",
      "isDefault": false,
      "registeredProviders": [],
      "environmentName": "AzureCloud"
    }
  ]
  ```

  You can get the following values from the output:

  * **SUBSCRIPTION-ID** - the row `id`.
  * **TENANT_ID**       - the row `tenantId`, please note it down for later use.

  >**NOTE:** If your **TENANT_ID** is not defined, one possibility is that you are using a personal account to log in to your Azure subscription. See [1.2 Configure Azure CLI](#configure_azure_cli) on how to fix this.

2. Ensure your default subscription is set to the one you want to create your service principal.

  ```
  azure account set <SUBSCRIPTION-ID>
  ```

  Example:

  ```
  azure account set 87654321-1234-5678-1234-678912345678
  ```

  Sample Output:

  ```
  info:    Executing command account set
  info:    Setting subscription to "Sample Subscription" with id "87654321-1234-5678-1234-678912345678".
  info:    Changes saved
  info:    account set command OK
  ```

## 2.2 Creating an Azure Active Directory (AAD) application

Create an AAD application with your information.

```
azure ad app create --name <name> --password <password> --home-page <home-page> --identifier-uris <identifier-uris>
```

* name: The display name for the application
* password: The value for the password credential associated with the application that will be valid for one year by default. This is your **CLIENT_SECRET**. Please note it down for later use.
* home-page: The URL to the application homepage. You can use a faked URL here.
* Identifier-uris: The comma-delimitied URIs that identify the application. You can use a faked URL here.

Example:

```
azure ad app create --name "Service Principal for BOSH" --password "password" --home-page "http://BOSHAzureCPI" --identifier-uris "http://BOSHAzureCPI"
```

Sample Output:

```
info:    Executing command ad app create
+ Creating application Service Principal for BOSH
data:    Application Id:          246e4af7-75b5-494a-89b5-363addb9f0fa
data:    Application Object Id:   a4f0d442-af80-4d98-9cba-6bf1459ad1ea
data:    Application Permissions:
data:                             claimValue:  user_impersonation
data:                             description:  Allow the application to access Service Principal for BOSH on behalf of the signed-in user.
data:                             directAccessGrantTypes:
data:                             displayName:  Access Service Principal for BOSH
data:                             impersonationAccessGrantTypes:  impersonated=User, impersonator=Application
data:                             isDisabled:
data:                             origin:  Application
data:                             permissionId:  1a1eb6d1-26ca-47de-abdb-365f54560e55
data:                             resourceScopeType:  Personal
data:                             userConsentDescription:  Allow the applicationto access Service Principal for BOSH on your behalf.
data:                             userConsentDisplayName:  Access Service Principal for BOSH
data:                             lang:
info:    ad app create command OK
```

* `Application Id` is your **CLIENT_ID** you need to create the service principal. Please note it down for later use.

## 2.3 Create a Service Principal

```
azure ad sp create $CLIENT_ID
```

Example:

```
azure ad sp create 246e4af7-75b5-494a-89b5-363addb9f0fa
```

Sample Output:

```
info:    Executing command ad sp create
+ Creating service principal for application 246e4af7-75b5-494a-89b5-363addb9f0fa
data:    Object Id:               fcf68d7a-262b-42c4-8ef8-6a4856611155
data:    Display Name:            Service Principal for BOSH
data:    Service Principal Names:
data:                             246e4af7-75b5-494a-89b5-363addb9f0fa
data:                             http://BOSHAzureCPI
info:    ad sp create command OK
```

You can get **service-principal-name** from any value of **Service Principal Names** to assign role to your service principal.

## 2.4 Assigning roles to your Service Principal

Now you have a service principal account, you need to grant this account access to proper resource use Azure CLI.

### 2.4.1 Assigning Roles

```
azure role assignment create --spn <service-principal-name> --roleName "Contributor" --subscription <subscription-id>
```

Example:

```
azure role assignment create --spn "http://BOSHAzureCPI" --roleName "Contributor" --subscription 87654321-1234-5678-1234-678912345678
```

You can verify the assignment with the following command:

```
azure role assignment list --spn <service-principal-name>
```

Sample Output:

```
data:    AD Object:
data:      ID:              7a3029f9-1b74-443e-8987-bed5b6f00009
data:      Type:            ServicePrincipal
data:      Display Name:    Service Principal for BOSH
data:      Principal Name:
data:    Scope:             /subscriptions/87654321-1234-5678-1234-678912345678
data:    Role:
data:      Name:            Contributor
data:      Permissions:
data:        Actions:      *
data:        NotActions:   Microsoft.Authorization/*/Write,Microsoft.Authorization/*/Delete
```

<a name="verify-your-service-principal"></a>
## 2.5 Verify Your Service Principal

Your service principal is created as follows:

- **TENANT_ID**
- **CLIENT_ID**
- **CLIENT_SECRET** 

Please verify it with the following steps:

1. Use Azure CLI to login with your service principal.

  You can find the `TENANT_ID`, `CLIENT_ID`, and `CLIENT_SECRET` properties in the `~/bosh.yml` file. If you cannot login, then the service principal is invalid.

  ```
  azure login --username $CLIENT_ID --password $CLIENT_SECRET --service-principal --tenant $TENANT_ID --environment $ENVIRONMENT
  ```

  Example:

  ```
  azure login --username 246e4af7-75b5-494a-89b5-363addb9f0fa --password "password" --service-principal --tenant 22222222-1234-5678-1234-678912345678 --environment AzureCloud
  ```

2. Verify that the subscription which the service principal belongs to is the same subscription that is used to create your resource group. (This may happen when you have multiple subscriptions.)

3. Recreate a service principal on your tenant if the service principal is invalid.

> **NOTE:** In some cases, if the service principal is invalid, then the deployment of BOSH will fail. Errors in `~/run.log` will show `get_token - http error` like this [reported issue](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/49).
