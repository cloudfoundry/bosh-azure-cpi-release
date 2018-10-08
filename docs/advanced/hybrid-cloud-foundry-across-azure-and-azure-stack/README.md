# Hybrid Cloud Foundry across Azure and Azure Stack

This guide will deploy two CF deployments, one on Azure and the other on Azure Stack. Operators can manage them using different API endpoints, and users can use a single endpoint to access application through Azure Traffic Manager.

## Pre-requisites

* An Azure account and Azure Stack account.
* Service principals for Azure and Azure Stack.
* A domain. `mslovelinux.com` is used in this guide.

Remove: * You can connect to Azure or Azure Stack with CLI or Powershell. Here's a [doc](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2) to use Azure CLI 2.0 in Azure Stack.

## Deploy Cloud Foundry seperately on Azure and Azure Stack

The [bosh-setup](https://github.com/Azure/azure-quickstart-templates/tree/master/bosh-setup) template supports both Azure and Azure Stack. For Azure Stack specific configurations, please refer to the [doc](https://github.com/cloudfoundry/bosh-azure-cpi-release/tree/master/docs/advanced/azure-stack).

We use the following configurations as an example.

| Deployment | Primary Deployment | Secondary Deployment |
|:----:|:--------:|:-----------:|
| Cloud | Azure | Azure Stack |
| Authentication | Azure AD | Azure AD |
| Managed Disks | Yes | No |
| Load Balancer | Standard SKU | Basic SKU |
| Storage Account | General-purpose v2 | General-purpose v1 |
| Cloud Foundry Blobstore | Azure Storage | Azure Stack Storage |
| Resource Group | ${PRIMARY_RESOURCE_GROUP_NAME} | ${SECONDARY_RESOURCE_GROUP_NAME} |
| System Domain | azure.mslovelinux.com | azurestack.mslovelinux.com |

Export the names of your two resource group as the environment variable `${PRIMARY_RESOURCE_GROUP_NAME}` and `${SECONDARY_RESOURCE_GROUP_NAME}`.

```
$ export PRIMARY_RESOURCE_GROUP_NAME="YOUR-PRIMARY-RESOURCE-GROUP-NAME"
$ export SECONDARY_RESOURCE_GROUP_NAME="YOUR-SECONDARY-RESOURCE-GROUP-NAME"
```

## Create a Traffic Manager Profile

1. Use Azure CLI to login your Azure account.

1. Create a traffic manager profile. Select `Performance` as the traffic-routing method, `TCP` as the Monitor Protocal and `443` as the Monitor Port.

    ```
    export TRAFFIC_MANAGER_DNS_NAME="cloudfoundry"
    az network traffic-manager profile create --name CloudFoundryTrafficManagerProfile --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --routing-method Performance --unique-dns-name ${TRAFFIC_MANAGER_DNS_NAME} --monitor-protocol TCP --monitor-port 443 --monitor-path ""
    ```

    `TRAFFIC_MANAGER_DNS_NAME` is the Relative DNS name for the traffic manager profile. Resulting FQDN will be `${TRAFFIC_MANAGER_DNS_NAME}.trafficmanager.net` and must be globally unique.

1. Create endpoints for two public IPs in Azure and Azure Stack. Select `External endpoints` as the endpoint type. For the location of Azure Stack endpoint, select the nearest location.

    ```
    az network traffic-manager endpoint create --name AzureEndpoint --profile-name CloudFoundryTrafficManagerProfile --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --type externalEndpoints --endpoint-location WestUS2 --target <PUBLIC_IP_ADDRESS_OF_LOAD_BALANCER_IN_AZURE>
    az network traffic-manager endpoint create --name AzureStackEndpoint --profile-name CloudFoundryTrafficManagerProfile --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --type externalEndpoints --endpoint-location WestUS --target <PUBLIC_IP_ADDRESS_OF_LOAD_BALANCER_IN_AZURE_STACK>
    ```

See more details in the [doc](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-create-profile).

## Create an Azure DNS Zone

1. Create a DNS zone

    ```
    export ZONE_NAME="mslovelinux.com"
    az network dns zone create --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --name ${ZONE_NAME}
    ```

1. Create DNS records

    1. Create records for `azure.mslovelinux.com` and `azurestack.mslovelinux.com`.

        ```
        az network dns record-set a create --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --name "*.azure"
        az network dns record-set a add-record --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --record-set-name "*.azure" --ipv4-address <PUBLIC_IP_ADDRESS_OF_LOAD_BALANCER_IN_AZURE>
        az network dns record-set a create --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --name "*.azurestack"
        az network dns record-set a add-record --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --record-set-name "*.azurestack" --ipv4-address <PUBLIC_IP_ADDRESS_OF_LOAD_BALANCER_IN_AZURE_STACK>
        ```

    1. Create records for `*.mslovelinux.com`.

        ```
        az network dns record-set cname create --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --name "*"
        az network dns record-set cname set-record --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --record-set-name "*" --cname "${TRAFFIC_MANAGER_DNS_NAME}.trafficmanager.net"
        ```

1. Confiure DNS server to Azure DNS

    1. Get your Name Server Domain Name. You can get four `nsdname` from the output.

        ```
        az network dns record-set ns show --resource-group ${PRIMARY_RESOURCE_GROUP_NAME} --zone-name ${ZONE_NAME} --name "@"
        ```

    1. Configure DNS server. It may differ from each provider, but the process is basically same. You can usually get the guidance in your domain-name service provider about how to configure your name server domain name.

## Deploy your Applications

### Login your Cloud Foundry

* SSH to your devbox on Azure, and login your Cloud Foundry.

    ```
    cf login -a https://api.azure.mslovelinux.com -u admin -p "$(bosh int ~/cf-deployment-vars.yml --path /cf_admin_password)" --skip-ssl-validation
    ```

* SSH to your devbox on Azure Stack, and login your Cloud Foundry.


    ```
    cf login -a https://api.azurestack.mslovelinux.com -u admin -p "$(bosh int ~/cf-deployment-vars.yml --path /cf_admin_password)" --skip-ssl-validation
    ```

### Install [Open Service Broker for Azure (OSBA)](https://github.com/CloudFoundryOnAzure/open-service-broker-azure)

1. Clone the `dev` branch of OSBA.

    ```
    git clone https://github.com/CloudFoundryOnAzure/open-service-broker-azure
    cd open-service-broker-azure/
    git fetch origin dev:dev
    git checkout dev
    ```

1. Install OSBA both on Azure and Azure Stack. Currently, OSBA doesn't support native services in Azure Stack. So, two OSBAs use service principals for Azure, and create services on Azure instead of Azure Stack.

    1. Create one resource group in `North Europe`.

        ```
        az group create --location northeurope --name cfdemo-services
        ```

    1. Create two redis caches: One (`osba-cache-north-europe`) is for OSBA in Azure, and the other (`osba-cache-west-us`) is for OSBA in Azure Stack.

        ```
        az redis create -n osba-cache-north-europe -g services -l northeurope --sku Basic --vm-size C1
        az redis create -n osba-cache-west-us -g services -l westus --sku Basic --vm-size C1
        ```

    1. Based on `contrib/cf/manifest.yml`, create two manifests for Azure and Azure Stack.

        1. Fill in the hostname and primarykey of two redis caches.

        1. Two manifests can use same service principal.
    
    1. Follow the [doc](https://github.com/CloudFoundryOnAzure/open-service-broker-azure/blob/master/contrib/cf/README.md) to push the broker to Cloud Foundry, and register the Service Broker.

    1. Expose services.

        In CF on Azure, run:

        ```
        cf enable-service-access azure-sql-12-0-dr-dbms-pair-registered
        cf enable-service-access azure-sql-12-0-dr-database-pair
        ```

        In CF on Azure Stack, run:

        ```
        cf enable-service-access azure-sql-12-0-dr-dbms-pair-registered
        cf enable-service-access azure-sql-12-0-dr-database-pair-registered
        ```

### Deploy a .NET core Application

[eShopOnWeb](https://github.com/CloudFoundryOnAzure/eShopOnWeb) is a sample ASP.NET Core reference application, demonstrating a single-process (monolithic) application architecture and deployment model. It needs a persistent database to store the identity and catalog data.

1. Create the services.

    In CF on Azure, run:

    ```
    cf create-service azure-sql-12-0-dr-dbms-pair-registered dbms sqlserverpair -c '{"primaryResourceGroup":"demo-services", "primaryLocation":"northeurope", "primaryServer":"cfdemosql1", "primaryAdministratorLogin":"<username>", "primaryAdministratorLoginPassword":"<password>", "secondaryResourceGroup":"demo-services", "secondaryServer":"cfdemosql2", "secondaryLocation":"westus", "secondaryAdministratorLogin":"<username>", "secondaryAdministratorLoginPassword":"<password>", "alias":"sqlserverpair"}'
    cf create-service azure-sql-12-0-dr-database-pair standard sqldbpair -c '{"parentAlias":"sqlserverpair", "database":"demo", "failoverGroup":"cfdemofg", "dtus": 100}'
    ```

    In CF on Azure Stack, run:

    ```
    cf create-service azure-sql-12-0-dr-dbms-pair-registered dbms sqlserverpair -c '{"primaryResourceGroup":"demo-services", "primaryLocation":"northeurope", "primaryServer":"cfdemosql1", "primaryAdministratorLogin":"<username>", "primaryAdministratorLoginPassword":"<password>", "secondaryResourceGroup":"demo-services", "secondaryServer":"cfdemosql2", "secondaryLocation":"westus", "secondaryAdministratorLogin":"<username>", "secondaryAdministratorLoginPassword":"<password>", "alias":"sqlserverpair"}'
    cf create-service azure-sql-12-0-dr-database-pair-registered database sqldbpair -c '{"parentAlias":"sqlserverpair", "database":"demo", "failoverGroup":"cfdemofg"}'
    ```

1. Setup a Concourse pipeline to push applications.

    The [pipeline](https://github.com/CloudFoundryOnAzure/concourse-pipeline-samples/tree/master/pipelines/azure/hybrid-scenario) will run tests, deploy `eShopOnWeb` to the CF deployment in Azure and Azure Stack and update the application route. 

    1. Login your concourse.

        ```
        fly -t dev login -c <concourse-url> --username=<username> --password="<password>"
        ```

    1. Copy [`credentials.yml.sample`](https://github.com/CloudFoundryOnAzure/concourse-pipeline-samples/blob/master/pipelines/azure/hybrid-scenario/credentials.yml.sample) to `credentials.yml`, and update the credentials.

    1. Create a pipeline.

        ```
        fly -t <target> set-pipeline -p <pipeline-name> -c pipeline.yml -l credentials.yml
        ```
