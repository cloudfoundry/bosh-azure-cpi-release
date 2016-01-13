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

1. Prepare a manifest
  * [A basic configuration](./get-started/prepare-manifest-for-cloudfoundry.md)
  * Advanced configurations (**OPTIONAL**) (Refer to the section "Deployment for Enterprise Environment")
2. [Deploy](./get-started/deploy-cloudfoundry.md)

# Deployment for Enterprise Environment

* [Deploy Cloud Foundry using multiple storage accounts and availability sets](./get-started/deploy-cloudfoundry-for-enterprise.md)

# Deployment for Diego with .NET support

* [Push your first .NET application to cloud foundry on Azure](./push-your-first-net-application-to-cloud-foundry-on-azure.md)

# Additional Information

If you hit some issues when you deploy BOSH and Cloud Foundry, you can refer to the following documents. If it does not work, please open an issue.

* [Troubleshooting](./get-started/troubleshooting.md)
* [Known issues](./get-started/known-issues.md)
* [Migration from Preview 2](./get-started/migration.md)
