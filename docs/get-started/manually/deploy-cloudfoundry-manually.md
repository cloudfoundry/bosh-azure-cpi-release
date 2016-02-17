# Deploy Cloud Foundry

>**NOTE:**
  * All the following commands must be run in your dev-box.
  * By default, this setction uses [xip.io](http://xip.io/) to resolve the system domain. More information, please click [**HERE**](../../advanced/deploy-azuredns).

## 1 Prepare the manifest for Cloud Foundry

>**NOTE:**
  * The section shows how to configure a get-started manifest to deploy Cloud Foundry. For a more robust deployment, please refer to [**deploy-cloudfoundry-for-enterprise**](../../advanced/deploy-cloudfoundry-for-enterprise/)

A manifest is needed to deploy Cloud Foundry. In this section, we will show how to configure the manifest.

We provide two sample configurations. You can choose one of them based on your needs.

* [**single-vm-cf-224.yml**](./single-vm-cf-224.yml): Configuration to deploy Single-VM Cloud Foundry.
* [**multiple-vm-cf-224.yml**](./multiple-vm-cf-224.yml): Configuration to deploy Multi-VM Cloud Foundry.

The following steps uses `single-vm-cf-224.yml` for an example.

1. Download the manifest.

  ```
  wget -O ~/single-vm-cf-224.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/get-started/manually/single-vm-cf-224.yml
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
  sed -i -e "s/REPLACE_WITH_DIRECTOR_ID/$(bosh status --uuid)/" ~/single-vm-cf-224.yml
  ```
  
3. Specify the following parameters

  * **REPLACE_WITH_VNET_NAME** - the virtual network name
  * **REPLACE_WITH_SUBNET_NAME_FOR_CLOUD_FOUNDRY** - the subnet name for Cloud Foundry
  * **REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP** - You can get the public IP for Cloud Foundry [**HERE**](./deploy-bosh-manually.md#get_public_ip). Another way is to find the IP from your resource group on Azure Portal.
  * **REPLACE_WITH_SSL_CERT_AND_KEY** - You should use your certificate and key. If you do not want to use yours, please use below script to generate a new one and update `REPLACE_WITH_SSL_CERT_AND_KEY` in your manifest automatically.

    ```
    openssl genrsa -out ~/haproxy.key 2048 &&
      echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
      cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
      awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY.*$",r))1' ~/single-vm-cf-224.yml > tmp &&
      mv -f tmp ~/single-vm-cf-224.yml
    ```

## 2 Deploy Cloud Foundry

1. Upload stemcell

  Get the value of **resource_pools.name[vms].stemcell.url** in [**bosh.yml**](https://github.com/Azure/azure-quickstart-templates/blob/master/bosh-setup/bosh.yml), then use it to replace **STEMCELL-FOR-AZURE-URL** in below command:

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

2. Upload Cloud Foundry release v224

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  ```

  >**NOTE:** If you want to use the latest Cloud Foundry version, the Azure part in the manifest is same but other configurations may be different. You need to change them manually.

3. Deploy

  ```
  bosh deployment PATH-TO-YOUR-MANIFEST-FOR-CLOUD-FOUNDRY
  bosh deploy
  ```

  >**NOTE:**
    * If you hit any issue, please see [**troubleshooting**](../../additional-information/troubleshooting.md), [**known issues**](../../additional-information/known-issues.md) and [**migration**](../../additional-information/migration.md). If it does not work, you can file an issue [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues).
