In this guide, you will learn how to run ASP.NET application on Cloud foundry with "cflinuxfs2" stack. If you need guide for running .NET application on Cloud foundry with "windows2012R2" stack, please go to this [guide](./run-asp-net-apps-with-windows2012R2-stack.md).

# Push your first .NET application to cloud foundry with "cflinuxfs2" stack on Azure

## 1 Prerequisites

* A deployment of Cloud Foundry with "cflinuxfs2" stack

  If you have followed the latest [guidance](../../guidance.md) via ARM templates on Azure to deploy BOSH and Cloud Foundry, you already have the environment ready.

## 2 Push your first ASP.NET application

1. Log on to your dev-box

2. Install CF CLI and the plugin

3. Configure your space

  Run `cat ~/settings | grep cf-ip` to get Cloud Foundry public IP.

  ```
  cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u USER -p PASSWORD
  cf create-space azure
  cf target -o "default_organization" -s "azure"
  ```

4. Download a demo ASP.NET application

  ```
  sudo apt-get -y install git
  git clone https://github.com/bingosummer/aspnet-core-helloworld
  ```

5. Push the application using ASP.NET buildpack. More info about ASP.NET buildpack, please refer to [link](https://github.com/cloudfoundry-community/dotnet-core-buildpack/blob/master/README.md)

  ```
  cd aspnet-core-helloworld
  cf push -b https://github.com/cloudfoundry-community/dotnet-core-buildpack.git
  ```

  You will see push log like:
  ```
  requested state: started
  instances: 1/1
  usage: 512M x 1 instances
  urls: sample-aspnetcore-helloworld-nondiphtherial-nonlogicality.52.187.41.119.xip.io
  last uploaded: Wed 17 Jul 22:57:04 UTC 2024
  stack: cflinuxfs2
  buildpack: https://github.com/cloudfoundry-community/dotnet-core-buildpack.git

       state     since                  cpu    memory          disk           logging         cpu entitlement   details
  #0   running   2024-07-17T22:57:22Z   0.3%   49.5M of 512M   130.2M of 1G   0B/s of 16K/s   2.4%
  ```
## 3 Verify your deployment completed successfully

1. Open your web browser, type http://sample-aspnetcore-helloworld-nondiphtherial-nonlogicality.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io/. Now you can see your ASP.NET Page.
