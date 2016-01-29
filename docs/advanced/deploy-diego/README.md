# Deploy Diego on Azure

## Before you begin ##

This document described the steps to deploy Diego for Cloud Foundry on Azure. It is assumed that you have already deployed your **BOSH director VM** on Azure by following this [guidance](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/guidance.md).

## Create a new subnet for Diego ##
1. Sign in to Azure portal.
2. Find your resource group which was created for your cloud foundry.
3. Find the virtual network **boshvnet-crp** in above resource group.
4. Create a new subnet
    - Name: **Diego**, CIDR: **10.0.32.0/20**

## Deploy you cloud foundry on Azure ##

1. Log on to your dev-box.

2. Download [single-vm-cf-224-diego.yml](../../example_manifests/single-vm-cf-224-diego.yml)

  ```
  wget -O ~/single-vm-cf-224-diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/example_manifests/single-vm-cf-224-diego.yml
  ```

3. Login to your BOSH director VM

  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin.
  ```

  _**Note:** If you have used ‘bosh logout’, you should use ‘bosh login admin admin’ to log in._

4. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169
  ```

5. Update **BOSH-DIRECTOR-UUID** in **~/single-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/BOSH-DIRECTOR-UUID/$(bosh status --uuid)/" ~/single-vm-cf-224-diego.yml
  ```

6. Update **SYSTEM-DOMAIN** in **~/single-vm-cf-224-diego.yml**

  Domains in Cloud Foundry provide a namespace from which to create routes. The presence of a domain in Cloud Foundry indicates to a developer that requests for any route created from the domain will be routed to Cloud Foundry. Cloud Foundry supports two domains, one is called **SYSTEM-DOMAIN** for system applications and one for general applications. To deploy Cloud Foundry, you need to specify the **SYSTEM-DOMAIN**, and it should be resolvable to an IP address.

  * If you deploy BOSH via [the bosh-setup template](../../get-started/deploy-bosh-using-arm-templates.md), DNS is setup by default which can resolve the domain `cf.azurelovecf.com`. In such a case, you can use `cf.azurelovecf.com` as the system domain name.

    ```
    sed -i -e "s/SYSTEM-DOMAIN/cf.azurelovecf.com/" ~/single-vm-cf-224-diego.yml
    ```

  * If you deploy BOSH via [the manual steps](../../get-started/deploy-bosh-manually.md) or set `enableDNSOnDevbox` as false in [the bosh-setup template](../../get-started/deploy-bosh-using-arm-templates.md), you need to setup DNS to resolve your domain by yourself.

    For quickly test, http://xip.io/ is an option to resolve your domain. For example:

    ```
    sed -i -e "s/SYSTEM-DOMAIN/$(cat ~/settings |grep cf-ip| sed 's/.*: "\(.*\)",/\1/').xip.io/" ~/single-vm-cf-224-diego.yml
    ```

7. Update CF **RESERVED-IP** in **~/single-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/RESERVED-IP/$(cat ~/settings |grep cf-ip| sed 's/.*: "\(.*\)",/\1/')/" ~/single-vm-cf-224-diego.yml
  ```

8. Update **SSL-CERT-AND-KEY** in **~/single-vm-cf-224-diego.yml**

  You should use your certificate and key. If you do not want to use yours, please use below command to generate a new one and update SSL-CERT-AND-KEY in ~/single-vm-cf-224-diego.yml automatically.

  ```
  openssl genrsa -out ~/haproxy.key 2048 &&
  echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
  cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
  awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY",r))1' ~/single-vm-cf-224-diego.yml > tmp &&
  mv -f tmp ~/single-vm-cf-224-diego.yml
  ```

9. Set BOSH deployment

  ```
  bosh deployment ~/single-vm-cf-224-diego.yml
  ```

10. Deploy cloud foundry

  ```
  bosh -n deploy
  ```

## Deploy Diego on Azure ##

1. Log on to your dev-box

2. Download [single-vm-diego.yml](../../example_manifests/single-vm-diego.yml)

  ```
  wget -O ~/single-vm-diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/example_manifests/single-vm-diego.yml
  ```

3. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/garden-linux-release?v=0.330.0
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/etcd-release?v=20
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/diego-release?v=0.1444.0
  ```

4. Update **BOSH-DIRECTOR-UUID** in **~/single-vm-diego.yml**

  ```
  sed -i -e "s/BOSH-DIRECTOR-UUID/$(bosh status --uuid)/" ~/single-vm-diego.yml
  ```

5. Update **SYSTEM-DOMAIN** in **~/single-vm-diego.yml**

  **Please keep it the same as the system domain name in **~/single-vm-cf-224-diego.yml**.

6. Set BOSH deployment

  ```
  bosh deployment ~/single-vm-diego.yml
  ```

7. Deploy Diego

  ```
  bosh -n deploy
  ```

## Configure CF Environment ##

1. Log on to your dev-box

2. Install CF CLI and the plugin

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  sudo dpkg -i cf.deb
  cf install-plugin Diego-Enabler -r CF-Community
  ```

3. Configure your space

  ```
  cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation -u admin -p c1oudc0w
  cf enable-feature-flag diego_docker
  cf create-org diego
  cf target -o diego
  cf create-space diego
  cf target -s diego
  ```

## Push your first application to Diego ##

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

  _**NOTE:**
  If you have not login to CF, you should use "cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation -u admin -p c1oudc0w" to login and select diego as your orgazination._
