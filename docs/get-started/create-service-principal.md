# Create a Service Principal - Azure CLI

This topic shows you how to permit a service principal (such as an automated process, application, or service) to access other resources in your subscription.

A service principal contains the following credentials which will be mentioned in this page. Please store them in a secure location because they are sensitive credentials.

- **TENANT_ID**
- **CLIENT_ID**
- **CLIENT_SECRET** 

# 1 Prepare Azure CLI

## 1.1 Install Azure CLI

Install and configure Azure CLI following the documentation [**HERE**](http://azure.microsoft.com/en-us/documentation/articles/xplat-cli/).

The following commands in this topic are based on Azure CLI version `0.9.18`.

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
data:    AppId:                   246e4af7-75b5-494a-89b5-363addb9f0fa
data:    ObjectId:                208096bb-4899-49e2-83ea-1a270154f427
data:    DisplayName:             Service Principal for BOSH
data:    IdentifierUris:          0=http://BOSHAzureCPI
data:    ReplyUrls:
data:    AvailableToOtherTenants:  False
info:    ad app create command OK
```

* `AppId` is your **CLIENT_ID** you need to create the service principal. Please note it down for later use.

## 2.3 Create a Service Principal

```
azure ad sp create --applicationId $CLIENT_ID
```

Example:

```
azure ad sp create --applicationId 246e4af7-75b5-494a-89b5-363addb9f0fa
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

`Contributor` can use terraform to bootstrap the environment

For more information about Azure Role-Based Access Control, please refer to [RBAC: Built-in roles](https://azure.microsoft.com/en-us/documentation/articles/role-based-access-built-in-roles/).

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
info:    Executing command role assignment list
+ Searching for role assignments
data:    RoleAssignmentId     : /subscriptions/87654321-1234-5678-1234-678912345678/providers/Microsoft.Authorization/roleAssignments/16645a17-3184-47c1-8e00-8eb1d0643d54
data:    RoleDefinitionName   : Contributor
data:    RoleDefinitionId     : b24988ac-6180-42a0-ab88-20f7382dd24c
data:    Scope                : /subscriptions/87654321-1234-5678-1234-678912345678
data:    Display Name         : CloudFoundry
data:    SignInName           :
data:    ObjectId             : 039ccb8a-5b34-4020-bff9-ba38bef98f61
data:    ObjectType           : ServicePrincipal
data:
info:    role assignment list command OK
```

By default, the scope of the role is set to the subscription. And it can also be assigned to one specific resource group or multiple resource groups if you want.

```
azure role assignment create --spn <service-principal-name> --roleName "Contributor" --resource-group <resource-group-name>
```

For example:

If you want to assign `Virtual Machine Contributor` role to only one resource group and `Network Contributor` role to two resource groups, you can use the following commands.

```
azure role assignment create --spn "http://BOSHAzureCPI" --roleName "Virtual Machine Contributor" --resource-group MyFirstRG
azure role assignment create --spn "http://BOSHAzureCPI" --roleName "Network Contributor" --resource-group MyFirstRG
azure role assignment create --spn "http://BOSHAzureCPI" --roleName "Network Contributor" --resource-group MySecondRG
```

The output of listing the roles:

```
$ azure role assignment list --spn "http://BOSHAzureCPI"
info:    Executing command role assignment list
+ Searching for role assignments
data:    RoleAssignmentId     : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MyFirstRG/providers/Microsoft.Authorization/roleAssignments/62db1b5a-e425-4c5d-8546-9290adb76221
data:    RoleDefinitionName   : Network Contributor
data:    RoleDefinitionId     : 4d97b98b-1d4f-4787-a291-c67834d212e7
data:    Scope                : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MyFirstRG
data:    Display Name         : Service Principal for BOSH
data:    SignInName           :
data:    ObjectId             : 87654321-1234-5678-1234-123456781234
data:    ObjectType           : ServicePrincipal
data:
data:    RoleAssignmentId     : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MyFirstRG/providers/Microsoft.Authorization/roleAssignments/ab9d2a39-251c-4d4b-9eb4-70ad2ed0e432
data:    RoleDefinitionName   : Virtual Machine Contributor
data:    RoleDefinitionId     : 9980e02c-c2be-4d73-94e8-173b1dc7cf3c
data:    Scope                : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MyFirstRG
data:    Display Name         : Service Principal for BOSH
data:    SignInName           :
data:    ObjectId             : 87654321-1234-5678-1234-123456781234
data:    ObjectType           : ServicePrincipal
data:
data:    RoleAssignmentId     : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MySecondRG/providers/Microsoft.Authorization/roleAssignments/eeafda2b-ae46-478b-9c40-924edb670dd3
data:    RoleDefinitionName   : Network Contributor
data:    RoleDefinitionId     : 4d97b98b-1d4f-4787-a291-c67834d212e7
data:    Scope                : /subscriptions/87654321-1234-5678-1234-678912345678/resourcegroups/MySecondRG
data:    Display Name         : Service Principal for BOSH
data:    SignInName           :
data:    ObjectId             : 87654321-1234-5678-1234-123456781234
data:    ObjectType           : ServicePrincipal
data:
info:    role assignment list command OK
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
