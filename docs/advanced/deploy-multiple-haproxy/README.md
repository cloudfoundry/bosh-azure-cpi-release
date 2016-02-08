# Deploy multiple HAProxy instances behind Azure Load Balancer

## Overview

This guidance describes how to setup multiple HAProxy instances for Cloud Foundry. Compared to a single instance of HAProxy, multiple HAProxy instances provide high-available load balancing functionalities to your Cloud Foundry traffic. 

The HAProxy instances will be setup behind the [Azure Load Balancer](https://azure.microsoft.com/en-us/documentation/articles/load-balancer-overview/), which is a Layer 4 (TCP, UDP) load balancer that distributes incoming traffic among healthy service instances. To provide redundancy, we also recommend that you group two or more HAproxy instances in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/).

Please note that this guidance focuses on CF deployment. You need to follow the [guidance](../../guidance.md) to prepare the Azure environment and deploy BOSH first. After you complete the section `Deploy BOSH`, you can follow this guidance for the rest Cloud Foundry deployment.

Below is a sample deployment, which you can adjust based on your workload and performance requirements. It is a multiple-VM Cloud Foundry with 2 HAProxy instances.

  ```
  +------------------------------------+---------+------------------+-------------+
  | Job/index                          | State   | Resource Pool    | IPs         |
  +------------------------------------+---------+------------------+-------------+
  | api_z1/0                           | running | resource_z1      | 10.0.16.101 |
  | doppler_z1/0                       | running | resource_z1      | 10.0.16.103 |
  | etcd_z1/0                          | running | resource_z1      | 10.0.16.14  |
  | ha_proxy_z1/0                      | running | resource_haproxy | 10.0.16.4   |
  | ha_proxy_z1/1                      | running | resource_haproxy | 10.0.16.5   |
  | hm9000_z1/0                        | running | resource_z1      | 10.0.16.102 |
  | loggregator_trafficcontroller_z1/0 | running | resource_z1      | 10.0.16.104 |
  | nats_z1/0                          | running | resource_z1      | 10.0.16.13  |
  | nfs_z1/0                           | running | resource_z1      | 10.0.16.15  |
  | postgres_z1/0                      | running | resource_z1      | 10.0.16.11  |
  | router_z1/0                        | running | resource_z1      | 10.0.16.12  |
  | router_z1/1                        | running | resource_z1      | 10.0.16.22  |
  | runner_z1/0                        | running | resource_z1      | 10.0.16.106 |
  | uaa_z1/0                           | running | resource_z1      | 10.0.16.105 |
  +------------------------------------+---------+------------------+-------------+
  ```

## Create Azure Load Balancer

Create an Azure Load Balancer named `haproxylb` using the [script](./create-load-balancer.sh). If you change the LB name in the script, you also need to update it in the CF manifest `multiple-vm-cf-224-multiple-haproxy.yml`.

Please update the value which starts with `REPLACE-ME` and run it after you [login Azure CLI](../../get-started/create-service-principal.md#verify-your-service-principal).

## Deploy Cloud Foundry with multiple HAProxy instances

1. Log on to your dev-box.

2. Download [multiple-vm-cf-224-multiple-haproxy.yml](./multiple-vm-cf-224-multiple-haproxy.yml)

  ```
  wget -O ~/multiple-vm-cf-224-multiple-haproxy.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/advanced/deploy-multiple-haproxy/multiple-vm-cf-224-multiple-haproxy.yml
  ```

3. Login to your BOSH director VM

  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin.
  ```

  _**Note:** If you have used `bosh logout`, you should use `bosh login admin admin` to log in._

4. Upload releases and stemcells

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169
  ```

5. Update **REPLACE_WITH_DIRECTOR_ID** in `~/multiple-vm-cf-224-multiple-haproxy.yml`

  ```
  sed -i -e "s/REPLACE_WITH_DIRECTOR_ID/$(bosh status --uuid)/" ~/multiple-vm-cf-224-multiple-haproxy.yml
  ```

6. Update **SYSTEM-DOMAIN** in `~/multiple-vm-cf-224-multiple-haproxy.yml`

  Domains in Cloud Foundry provide a namespace from which to create routes. The presence of a domain in Cloud Foundry indicates to a developer that requests for any route created from the domain will be routed to Cloud Foundry. Cloud Foundry supports two domains, one is called **SYSTEM-DOMAIN** for system applications and one for general applications. To deploy Cloud Foundry, you need to specify the **SYSTEM-DOMAIN**, and it should be resolvable to an IP address.

  * For production environments, you need to setup DNS to resolve your **SYSTEM-DOMAIN**.

  * For test environments, http://xip.io/ is an option to resolve your domain.

    The following command is an example to use the default reserved IP for Cloud Foundry. You can use any other reserved IP if you don't want to use the default one.

    ```
    sed -i -e "s/SYSTEM-DOMAIN/$(cat ~/settings |grep cf-ip| sed 's/.*: "\(.*\)", /\1/').xip.io/" ~/multiple-vm-cf-224-multiple-haproxy.yml
    ```

7. Update **SSL-CERT-AND-KEY** in `~/multiple-vm-cf-224-multiple-haproxy.yml`

  You can either use your existing SSL certificate and key or follow below commands to generate a new one and update **SSL-CERT-AND-KEY** in ~/multiple-vm-cf-224-multiple-haproxy.yml automatically.

  ```
  openssl genrsa -out ~/haproxy.key 2048 &&
  echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
  cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
  awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY",r))1' ~/multiple-vm-cf-224-multiple-haproxy.yml > tmp &&
  mv -f tmp ~/multiple-vm-cf-224-multiple-haproxy.yml
  ```

8. Set BOSH deployment

  ```
  bosh deployment ~/multiple-vm-cf-224-multiple-haproxy.yml
  ```

9. Deploy cloud foundry

  ```
  bosh -n deploy
  ```
