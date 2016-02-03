# Deploy Cloud Foundry on Azure

# Overview

This document describes how to deploy [BOSH](http://bosh.io/) and [Cloud Foundry](https://www.cloudfoundry.org/) on [Azure](https://azure.microsoft.com/en-us/).

# Prerequisites

* [Creating an Azure account](https://azure.microsoft.com/en-us/pricing/free-trial/)

# Get Started

## Create a Service Principal

[**HERE**](./get-started/create-service-principal.md) is how to create a service principal.

## Deploy BOSH

You have two options to deploy BOSH on Azure. One is ARM templates which can help you automatically prepare essential resources to deploy BOSH, the other is manual steps.

  * [Deploy BOSH using ARM templates (**RECOMMENDED**)](./get-started/deploy-bosh-using-arm-templates.md)
  * [Deploy BOSH manually](./get-started/deploy-bosh-manually.md)

## Deploy Cloud Foundry

1. [Prepare a manifest for a basic configuration](./get-started/prepare-manifest-for-cloudfoundry.md)
2. [Deploy](./get-started/deploy-cloudfoundry.md)

# Advanced Configurations and Deployments

* [Deploy Cloud Foundry using multiple storage accounts and availability sets](./advanced/deploy-cloudfoundry-for-enterprise.md)
* [Push your first .NET application to Cloud Foundry on Azure](./advanced/push-your-first-net-application-to-cloud-foundry-on-azure/)
* [Integrating Application Gateway with Cloud Foundry on Azure](./advanced/application-gateway/)
* [Deploy MySQL Service to Cloud Foundry on Azure](./advanced/deploy-mysql/)
* [Deploy Mongodb Service to Cloud Foundry on Azure](./advanced/deploy-mongodb/)

# Additional Information

If you hit some issues when you deploy BOSH and Cloud Foundry, you can refer to the following documents. If it does not work, please open an issue.

* [Troubleshooting](./get-started/troubleshooting.md)
* [Known issues](./get-started/known-issues.md)
* [Migration from Preview 2](./get-started/migration.md)
