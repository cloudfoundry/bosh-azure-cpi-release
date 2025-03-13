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

* [Deploy BOSH](https://bosh.io/docs/init-azure.html)
* [Deploy Cloud Foundry](https://docs.cloudfoundry.org/deploying/azure/index.html)

## 2.3 Push Your First Application

In this step, you will install Cloud Foundry Command Line Interface and push your first APP.

* [Push Your First Application](./get-started/push-demo-app.md)

# 3 Advanced Configurations and Deployments

* CPI Settings
  * [Use availability zones in Cloud Foundry](./advanced/availability-zone/)
  * [Deploy Cloud Foundry using availability sets](./advanced/deploy-cloudfoundry-with-availability-sets/)
  * [Use Standard SKU Load Balancers](./advanced/standard-load-balancers)
  * [Migrate Basic SKU Load Balancer to Standard SKU Load Balancer](./advanced/migrate-basic-lb-to-standard-lb/)
  * [Use managed disks in Cloud Foundry](./advanced/managed-disks/)
  * [Deploy Cloud Foundry using multiple storage accounts](./advanced/deploy-cloudfoundry-with-multiple-storage-accounts/)
  * [Configure resource groups](./advanced/configure-resource-groups/)
  * [Deploy multiple network interfaces for a Cloud Foundry instance](./advanced/deploy-multiple-network-interfaces/)
  * [Use application security groups in Cloud Foundry](./advanced/application-security-groups/)
  * [Use service principal with certificate](./advanced/use-service-principal-with-certificate/)
  * [Calculate correct VM cloud properties based on `vm_resources`](./advanced/calculate-vm-cloud-properties/)
  * [Use Azure Accelerated Networking](./advanced/accelerated-networking/)
  * [Use Azure Managed Identity](./advanced/managed-identity/)

# 4 Additional Information

If you hit some issues when you deploy BOSH and Cloud Foundry, you can refer to the following documents. If it does not work, please open an issue.

* [Known issues](./additional-information/known-issues.md)
* [Troubleshooting](./additional-information/troubleshooting.md)
* [Collect deployment error logs](./additional-information/collect-deployment-err-logs.md)
