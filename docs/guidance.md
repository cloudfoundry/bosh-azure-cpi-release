# Deploy Cloud Foundry on Azure

In Microsoft Azure, there are serveral different environments, such as AzureCloud for global Azure, AzureUSGovernment for Azure Government, and AzureChinaCloud for Azure operated by 21Vianet in China.

This document describes how to deploy [BOSH](http://bosh.io/) and [Cloud Foundry](https://www.cloudfoundry.org/) on:
* [AzureCloud](https://azure.microsoft.com/en-us/)
* [AzureChinaCloud](https://www.azure.cn/)
* [AzureGermanCloud](https://azure.microsoft.com/en-us/overview/clouds/germany/)
* [AzureUSGovernment](http://www.azure.com/gov)
* [AzureStack](https://azure.microsoft.com/en-us/overview/azure-stack/)

# 1 Prerequisites

You can create an Azure account according to the environment where Cloud Foundry will be deployed.

* [Creating an Azure account for AzureCloud](https://azure.microsoft.com/en-us/pricing/free-trial/)
* [Creating an Azure account for AzureChinaCloud](https://www.azure.cn/pricing/pia/)
* [Creating an Azure account for AzureGermanCloud](https://azure.microsoft.com/en-us/free/germany/)
* [Creating an Azure account for AzureUSGovernment](https://azuregov.microsoft.com/trial/azuregovtrial)

# 2 Get Started

## 2.1 Create a Service Principal

[**HERE**](./get-started/create-service-principal.md) is how to create a service principal.

## 2.2 Deploy BOSH and Cloud Foundry

You have two options to deploy BOSH and Cloud Foundry on Azure. One is ARM templates which can help you automatically prepare essential resources, the other is manual steps.

### 2.2.1 Via ARM templates (**RECOMMENDED**)

* [Deploy BOSH](./get-started/via-arm-templates/deploy-bosh-via-arm-templates.md)
* [Deploy Cloud Foundry](./get-started/via-arm-templates/deploy-cloudfoundry-via-arm-templates.md)

### 2.2.2 Manually

* [Deploy BOSH](https://bosh.io/docs/init-azure.html)
* [Deploy Cloud Foundry](https://docs.cloudfoundry.org/deploying/azure/index.html)

## 2.3 Push Your First Application

In this step, you will install Cloud Foundry Command Line Interface and push your first APP.

* [Push Your First Application](./get-started/push-demo-app.md)

# 3 Advanced Configurations and Deployments

* CPI Settings
  * [Use availability zones in Cloud Foundry](./advanced/availability-zone/)
  * [Deploy Cloud Foundry using availability sets](./advanced/deploy-cloudfoundry-with-availability-sets/)
  * [Use managed disks in Cloud Foundry](./advanced/managed-disks/)
  * [Deploy Cloud Foundry using multiple storage accounts](./advanced/deploy-cloudfoundry-with-multiple-storage-accounts/)
  * [Configure resource groups](./advanced/configure-resource-groups/)
  * [Deploy multiple network interfaces for a Cloud Foundry instance](./advanced/deploy-multiple-network-interfaces/)
  * [Use application security groups in Cloud Foundry](./advanced/application-security-groups/)
  * [Deploy Cloud Foundry on Azure Stack](./advanced/azure-stack/)
  * [Use service principal with certificate](./advanced/use-service-principal-with-certificate/)
  * [Calculate correct VM cloud properties based on `vm_resources`](./advanced/calculate-vm-cloud-properties/)
* Cloud Foundry Scenarios
  * [Configure Cloud Foundry external databases using Azure MySQL/Postgres Service](./advanced/configure-cf-external-databases-using-azure-mysql-postgres-service)
  * [Integrating Application Gateway](./advanced/application-gateway/)
  * [Push your first .NET application to Cloud Foundry on Azure](./advanced/push-your-first-net-application-to-cloud-foundry-on-azure/)
  * [Integrating Traffic Manager](./advanced/traffic-manager/)
  * [Backup and restore Cloud Foundry](./advanced/backup-and-restore-cloud-foundry/)
  * [SSH into the application](./advanced/cf-ssh-application/)
  * [Deploy multiple HAProxy instances behind Azure Load Balancer](./advanced/deploy-multiple-haproxy/)
  * [Update Cloud Foundry to use Diego](./advanced/switch-to-diego-default-architecture/)
  * [Azure DNS](./advanced/deploy-azuredns/)
* Service Brokers
  * [Meta Azure Service Broker](https://github.com/Azure/meta-azure-service-broker)
  * [MySQL Service](./advanced/deploy-mysql/)

# 4 Additional Information

If you hit some issues when you deploy BOSH and Cloud Foundry, you can refer to the following documents. If it does not work, please open an issue.

* [Known issues](./additional-information/known-issues.md)
* [Troubleshooting](./additional-information/troubleshooting.md)
* [Collect deployment error logs](./additional-information/collect-deployment-err-logs.md)
