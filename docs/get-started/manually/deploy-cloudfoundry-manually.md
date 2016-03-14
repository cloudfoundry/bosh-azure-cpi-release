# Deploy Cloud Foundry

>**NOTE:**
  * All the following commands must be run in your dev-box.
  * By default, this setction uses [xip.io](http://xip.io/) to resolve the system domain. More information, please click [**HERE**](../../advanced/deploy-azuredns).

## 1 Prepare the manifest for Cloud Foundry

>**NOTE:**
  * The section shows how to configure a get-started manifest to deploy Cloud Foundry. For a more robust deployment, please refer to [**deploy-cloudfoundry-for-enterprise**](../../advanced/deploy-cloudfoundry-for-enterprise/)

A manifest is needed to deploy Cloud Foundry. In this section, we will show how to configure the manifest.

We provide two sample configurations. You can choose one of them based on your needs.

* [**single-vm-cf.yml**](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/abelhu/bosh-setup/manifests/single-vm-cf.yml): Configuration to deploy Single-VM Cloud Foundry.
* [**multiple-vm-cf.yml**](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/abelhu/bosh-setup/manifests/multiple-vm-cf.yml): Configuration to deploy Multi-VM Cloud Foundry.

The following steps uses `single-vm-cf.yml` for an example.

1. Download the manifest.

  ```
  wget -O ~/single-vm-cf.yml https://raw.githubusercontent.com/Azure/azure-quickstart-templates/abelhu/bosh-setup/manifests/single-vm-cf.yml
  ```

2. Specify **REPLACE_WITH_DIRECTOR_ID**.

  Logon your BOSH director with below command.
  
  ```
  bosh target <BOSH-DIRECTOR-IP> # Username: admin, Password: admin
  ```

  `<BOSH-DIRECTOR-IP>` is defined in `bosh.yml`.

  Example:

  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin
  ```
  
  Get the UUID of your BOSH director, and specify **REPLACE_WITH_DIRECTOR_ID**.
  
  ```
  sed -i -e "s/REPLACE_WITH_DIRECTOR_ID/$(bosh status --uuid)/" ~/single-vm-cf.yml
  ```
  
3. Specify the following parameters

  * **REPLACE_WITH_SUBNET_ADDRESS_RANGE_FOR_CLOUD_FOUNDRY** - the CIDR for Cloud Foundry subnet, e.g., 10.0.16.0/20
  * **REPLACE_WITH_GATEWAY_IP** - the gateway for Cloud Foundry subnet, e.g., 10.0.16.1
  * **REPLACE_WITH_RESERVED_IP_FROM** - the reserved IP address for Cloud Foundry subnet, e.g., 10.0.16.2
  * **REPLACE_WITH_RESERVED_IP_TO** - the reserved IP address for Cloud Foundry subnet, e.g., 10.0.16.3
  * **REPLACE_WITH_STATIC_IP** - the static IP for Cloud Foundry VM, e.g., 10.0.16.4
  * **REPLACE_WITH_VNET_NAME** - the virtual network name, e.g., boshvnet-crp
  * **REPLACE_WITH_SUBNET_NAME_FOR_CLOUD_FOUNDRY** - the subnet name for Cloud Foundry, e.g., CloudFoundry
  * **REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP** - You can get the public IP for Cloud Foundry [**HERE**](./deploy-bosh-manually.md#get_public_ip). Another way is to find the IP from your resource group on Azure Portal.
  * **REPLACE_WITH_CLOUD_FOUNDRY_INTERNAL_IP** - the static IP for Cloud Foundry VM, e.g., 10.0.16.4
  * **REPLACE_WITH_SYSTEM_DOMAIN** - You should use your domain name. If you do not want to use yours, you can use 'REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io'.
  * **REPLACE_WITH_SSL_CERT_AND_KEY** - You should use your certificate and key. If you do not want to use yours, please use below script to generate a new one and update `REPLACE_WITH_SSL_CERT_AND_KEY` in your manifest automatically.

    ```
    openssl genrsa -out ~/haproxy.key 2048 &&
      echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
      cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
      awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("REPLACE_WITH_SSL_CERT_AND_KEY.*$",r))1' ~/single-vm-cf.yml > tmp &&
      mv -f tmp ~/single-vm-cf.yml
    ```

## 2 Deploy Cloud Foundry

1. Upload stemcell

  Get the value of **resource_pools.name[vms].stemcell.url** in [**bosh.yml**](https://github.com/Azure/azure-quickstart-templates/blob/master/bosh-setup/bosh.yml), or get the value from [**Azure Hyper-V Stemcells based on Ubuntu**](http://bosh.io/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent). Then use it to replace **STEMCELL-FOR-AZURE-URL** in below command:

  ```
  bosh upload stemcell STEMCELL-FOR-AZURE-URL
  ```

  You can verify it using `bosh stemcells`.
  
  Sample Output:
  
  ```
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | Name                                     | OS            | Version | CID                                                |
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  | bosh-azure-hyperv-ubuntu-trusty-go_agent | ubuntu-trusty | XXXX*   | bosh-stemcell-a5670316-2774-4d65-8853-afd956c33f61 |
  +------------------------------------------+---------------+---------+----------------------------------------------------+
  ```

2. Upload Cloud Foundry release

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=231
  ```

  >**NOTE:** If you want to use the latest Cloud Foundry version, the Azure part in the manifest is same but other configurations may be different. You need to change them manually.

3. Deploy

  ```
  bosh deployment ~/single-vm-cf.yml
  bosh -n deploy
  ```

  >**NOTE:**
    * If you hit any issue, please see [**troubleshooting**](../../additional-information/troubleshooting.md), [**known issues**](../../additional-information/known-issues.md) and [**migration**](../../additional-information/migration.md). If it does not work, you can file an issue [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues).
