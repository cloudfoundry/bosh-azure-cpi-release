# Deploy Cloud Foundry on Azure

In Microsoft Azure, there are serveral different environments, such as AzureCloud for global Azure and AzureChinaCloud for Azure operated by 21Vianet in China.

This document describes how to deploy [BOSH](http://bosh.io/) and [Cloud Foundry](https://www.cloudfoundry.org/) on [AzureCloud](https://azure.microsoft.com/en-us/) and [AzureChinaCloud](https://www.azure.cn/).

# 1 Prerequisites

You can create an Azure account according to the environment where Cloud Foundry will be deployed.

* [Creating an Azure account for AzureCloud](https://azure.microsoft.com/en-us/pricing/free-trial/)
* [Creating an Azure account for AzureChinaCloud](https://www.azure.cn/pricing/pia/)

<a name="get-started"/>
# 2 Get Started

## 2.1 Create a Service Principal

[**HERE**](./get-started/create-service-principal.md) is how to create a service principal.

## 2.2 Deploy BOSH and Cloud Foundry

You have two options to deploy BOSH and Cloud Foundry on Azure. One is ARM templates which can help you automatically prepare essential resources, the other is manual steps.

### 2.2.1 Via ARM templates (**RECOMMENDED**)

* [Deploy BOSH](./get-started/via-arm-templates/deploy-bosh-via-arm-templates.md)
* [Deploy Cloud Foundry](./get-started/via-arm-templates/deploy-cloudfoundry-via-arm-templates.md)

### 2.2.2 Manually

* [Deploy BOSH](./get-started/manually/deploy-bosh-manually.md)
* [Deploy Cloud Foundry](./get-started/manually/deploy-cloudfoundry-manually.md)

## 2.3 Push Your First Application

In this step, you will install Cloud Foundry Command Line Interface and push your first APP.

* [Push Your First Application](./get-started/push-demo-app.md)

# 3 Advanced Configurations and Deployments

* [Deploy Cloud Foundry using multiple storage accounts and availability sets](./advanced/deploy-cloudfoundry-for-enterprise/)
* [Deploy Diego](./advanced/deploy-diego/)
* [Push your first .NET application to Cloud Foundry on Azure](./advanced/push-your-first-net-application-to-cloud-foundry-on-azure/)
* Service Brokers
  * [MySQL Service](./advanced/deploy-mysql/)
  * [Mongodb Service](./advanced/deploy-mongodb/)
* Integrate Azure Services with Cloud Foundry on Azure
  * [Azure DNS](./advanced/deploy-azuredns/)
  * [Deploy multiple HAProxy instances behind Azure Load Balancer](./advanced/deploy-multiple-haproxy/)

# 4 Additional Information

If you hit some issues when you deploy BOSH and Cloud Foundry, you can refer to the following documents. If it does not work, please open an issue.

* [Known issues](./additional-information/known-issues.md)
* [Troubleshooting](./additional-information/troubleshooting.md)
* [Migration from Preview 2](./additional-information/migration.md)
