# Deploy Diego on Azure

This document described the steps to deploy Diego for Cloud Foundry on Azure.

## 1 Prerequisites

* A deployment of BOSH

  It is assumed that you have already deployed your **BOSH director VM** and **Cloud Foundry** on Azure by following the [guidance](../../guidance.md) via ARM templates and did not change any settings, for example, network CIDR.

  1. Log on to your dev-box.

  2. Login to your BOSH director VM

    ```
    bosh target 10.0.0.4 # Username: admin, Password: admin.
    ```

    >**NOTE:** If you have used `bosh logout`, you should use `bosh login admin admin` to log in.

* A new subnet for Diego

  1. Sign in to Azure portal.
  2. Find your resource group which was created for your Cloud Foundry.
  3. Find the virtual network in above resource group.
  4. Create a new subnet
      - Name: **Diego**, CIDR: **10.0.32.0/20**


## Manifests

We provide below manifests for you to deploy Diego for testing.

* Single VM Version
  * [single-vm-diego.yml](./single-vm-diego.yml)
* Multiple VM Version
  * [multiple-vm-diego.yml](./multiple-vm-diego.yml)

In this document, we will use the single-vm manifest as an example.

## 2 Update Cloud Foundry

1. Update your cloud foundry manifest ~/example_manifests/single-vm-cf.yml or ~/example_manifests/multiple-vm-cf.yml.

  ```
    jobs:
    - name: api_z1
      properties:
        nfs_server:
          allow_from_entries: [10.0.16.0/20]
    =>
    jobs:
    - name: api_z1
      properties:
        nfs_server:
          allow_from_entries: [10.0.16.0/20, 10.0.32.0/20]
  ```

  ```
    properties:
      nfs_server:
        allow_from_entries: [10.0.16.0/20]
    =>
    properties:
      nfs_server:
        allow_from_entries: [10.0.16.0/20, 10.0.32.0/20]
  ```

2. Update your cloud foundry.

  ```
  bosh -n deploy
  ```

  >**NOTE:** When updating your cloud foundry, you may hit below error. You can ignore it.

  ```
      Failed updating job ha_proxy_z1 > ha_proxy_z1/0 (ad06f763-9eb2-4db3-a318-2367b7f47bbd) (canary): `ha_proxy_z1/0 (ad06f763-9eb2-4db3-a318-2367b7f47bbd)' is not running after update. Review logs for failed jobs: haproxy_config, haproxy (00:10:12)
    Error 400007: `ha_proxy_z1/0 (ad06f763-9eb2-4db3-a318-2367b7f47bbd)' is not running after update. Review logs for failed jobs: haproxy_config, haproxy
  ```

## 3 Deploy Diego on Azure

1. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/garden-linux-release?v=0.334.0
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/etcd-release?v=36
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/diego-release?v=0.1455.0
  ```

2. Download [single-vm-diego.yml](./single-vm-diego.yml)

  ```
  wget -O ~/single-vm-diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/advanced/deploy-diego/single-vm-diego.yml
  ```

3. Update **REPLACE_WITH_DIRECTOR_ID** in **~/single-vm-diego.yml**

  ```
  sed -i -e "s/REPLACE_WITH_DIRECTOR_ID/$(bosh status --uuid)/" ~/single-vm-diego.yml
  ```

4. Update **REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP** in **~/single-vm-diego.yml**

  ```
  sed -i -e "s/REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP/$(cat ~/settings | grep cf-ip | sed 's/.*: "\(.*\)", /\1/')/" ~/single-vm-diego.yml
  ```

5. Set BOSH deployment to diego

  ```
  bosh deployment ~/single-vm-diego.yml
  ```

6. Deploy Diego

  ```
  bosh -n deploy
  ```

  >**NOTE:** You may hit the issue "`diego_z1/0` is not running after update". You can run 'bosh -n deploy' again.

## 3 Configure CF Environment

1. Log on to your dev-box

2. Install CF CLI and the plugin

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  sudo dpkg -i cf.deb
  cf install-plugin Diego-Enabler -r CF-Community
  ```

3. Configure your space

  Run `cat ~/settings | grep cf-ip` to get Cloud Foundry public IP.

  ```
  cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u admin -p c1oudc0w
  cf enable-feature-flag diego_docker
  cf create-org diego
  cf target -o diego
  cf create-space diego
  cf target -s diego
  ```

## 5 Push your first application to Diego

1. Log on to your dev-box

2. Download a demo application and extract it

  ```
  sudo apt-get -y install git
  git clone https://github.com/bingosummer/2048
  ```

3. Push the application

  ```
  cd 2048
  cf push --no-start
  cf enable-diego game-2048
  cf start game-2048
  ```

  >**NOTE:**
    You can use `cf ssh game-2048` to ssh into the running container for your application.

## 6 Known Issues

1. When executing 'cf start game-2048', you may hit below errors. Just retry it.

  Error:
  ```
  $ cf start game-2048
  Starting app game-2048 in org diego / space diego as admin...
  FAILED
  Server error, status code: 500, error code: 10001, message: An unknown error occurred.
  ```

  ```
  $ cf start game-2048
  Starting app game-2048 in org diego / space diego as admin...
  FAILED
  Server error, status code: 500, error code: 170011, message: Stager error: getaddrinfo: No address associated with hostname
  ```