# Prepare the manifest for Cloud Foundry

>**NOTE:**
  * The section shows how to configure a get-started manifest to deploy Cloud Foundry. For a more robust deployment, please refer to [**deploy-cloudfoundry-for-enterprise**](./deploy-cloudfoundry-for-enterprise.md)
  * All the following commands must be run in your dev-box.

A manifest is needed to deploy Cloud Foundry. In this section, we will show how to configure the manifest.

We provide two sample configurations:

* [**single-vm-cf-224.yml**](../example_manifests/single-vm-cf-224.yml): Configuration to deploy Single-VM Cloud Foundry.
* [**multiple-vm-cf-224.yml**](../example_manifests/multiple-vm-cf-224.yml): Configuration to deploy Multi-VM Cloud Foundry.

You can choose one of them based on your needs.

You should replace the **BOSH-DIRECTOR-UUID**, **VNET-NAME**, **SUBNET-NAME**, **RESERVED-IP** and **SSL-CERT-AND-KEY** properties.

1. Configure **BOSH-DIRECTOR-UUID**

  Logon your BOSH director with below command.
  
  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin
  ```
  
  Get the UUID of your BOSH director with below command.
  
  ```
  bosh status
  ```
  
  Copy **Director.UUID** to replace **BOSH-DIRECTOR-UUID** in the YAML file for Cloud Foundry.
  
  Sample output:
  
  ```
  Config
       /home/vcap/.bosh_config
  
  Director
  Name       bosh
  URL        https://10.0.0.4:25555
  Version    1.0000.0 (00000000)
  User       admin
  UUID       640a7bf6-a39c-414e-83b9-d1bef9d6f701
  CPI        cpi
  dns        disabled
  compiled_package_cache disabled
  snapshots  enabled
  
  Deployment
  not set
  ```

2. Configure **VNET-NAME**, **SUBNET-NAME** and **RESERVED-IP**

  * **VNET-NAME** - the virtual network name
  * **SUBNET-NAME** - the subnet name for Cloud Foundry
  * **RESERVED-IP**
    * If your BOSH is deployed using ARM templates, you can find `cf-ip` in `~/settings`.
    * If your BOSH is deployed manually, you can get the public IP for Cloud Foundry [**HERE**](./deploy-bosh-manually.md#get_public_ip). Another way is to find the IP from your resource group on Azure Portal.

3. Configure **SSL-CERT-AND-KEY**

  You should use your certificate and key to replace SSL-CERT-AND-KEY. If you do not want to use yours, please use below script to generate a new one and update SSL-CERT-AND-KEY in your manifest automatically.
  Below script uses ~/single-vm-cf-224.yml for an example.

  ```
  openssl genrsa -out ~/haproxy.key 2048 &&
    echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
    cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
    awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY.*$",r))1' ~/single-vm-cf-224.yml > tmp &&
    mv -f tmp ~/single-vm-cf-224.yml
  ```

>**NOTE:**
  * If you set `enableDNSOnDevbox` true, the dev box can serve as a DNS and it has been pre-configured in example YAML file.
  * If you want to use your own domain name, you can replace all **cf.azurelovecf.com** in the example YAML file. And please replace **10.0.0.100** with the IP address of your DNS server.
