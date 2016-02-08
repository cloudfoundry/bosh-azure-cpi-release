# Deploy Diego on Azure

This document described the steps to deploy Diego for Cloud Foundry on Azure.

## 1 Prerequisites

* A deployment of BOSH

  It is assumed that you have already deployed your **BOSH director VM** on Azure by following this [guidance](../../guidance.md).

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

We provide the manifests for Cloud Foundry and Diego.

* Single VM Version
  * [single-vm-cf-224-diego.yml](./single-vm-cf-224-diego.yml)
  * [single-vm-diego.yml](./single-vm-diego.yml)
* Multiple VM Version
  * [multiple-vm-cf-224-diego.yml](./multiple-vm-cf-224-diego.yml)
  * [multiple-vm-diego.yml](./multiple-vm-diego.yml)

You can deploy Cloud Foundry and Diego using the single-vm manifest or the multiple-vm manifest. In this document, we will use the single-vm manifest as an example.
 
## 2 Deploy your Cloud Foundry on Azure

1. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169
  ```

2. Download [single-vm-cf-224-diego.yml](./single-vm-cf-224-diego.yml)

  ```
  wget -O ~/single-vm-cf-224-diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/advanced/deploy-diego/single-vm-cf-224-diego.yml
  ```

3. Update **REPLACE_WITH_DIRECTOR_ID** in **~/single-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/REPLACE_WITH_DIRECTOR_ID/$(bosh status --uuid)/" ~/single-vm-cf-224-diego.yml
  ```

4. Update **REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP** in **~/single-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP/$(cat ~/settings | grep cf-ip | sed 's/.*: "\(.*\)", /\1/')/" ~/single-vm-cf-224-diego.yml
  ```

5. Update **SSL-CERT-AND-KEY** in **~/single-vm-cf-224-diego.yml**

  You should use your certificate and key. If you do not want to use yours, please use below command to generate a new one and update SSL-CERT-AND-KEY in ~/single-vm-cf-224-diego.yml automatically.

  ```
  openssl genrsa -out ~/haproxy.key 2048 &&
  echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
  cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
  awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY",r))1' ~/single-vm-cf-224-diego.yml > tmp &&
  mv -f tmp ~/single-vm-cf-224-diego.yml
  ```

6. Set BOSH deployment

  ```
  bosh deployment ~/single-vm-cf-224-diego.yml
  ```

7. Deploy Cloud Foundry

  ```
  bosh -n deploy
  ```

## 3 Deploy Diego on Azure

1. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/garden-linux-release?v=0.330.0
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/etcd-release?v=20
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/diego-release?v=0.1444.0
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

5. Set BOSH deployment

  ```
  bosh deployment ~/single-vm-diego.yml
  ```

6. Deploy Diego

  ```
  bosh -n deploy
  ```

  >**NOTE:** You may hit the issue "`diego_z1/0` is not running after update", please check [#85](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/85). Workaround:

    ```
    bosh ssh diego_z1
    sudo su
    monit quit etcd
    monit quit bbs
    killall -9 etcd
    monit start all
    ```

## 4 Configure CF Environment

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
