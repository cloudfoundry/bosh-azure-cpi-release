# Deploy multiple HAProxy instances behind Azure Load Balancer

## Overview

This guidance describes how to setup multiple HAProxy instances for Cloud Foundry. Compared to a single instance of HAProxy, multiple HAProxy instances provide high-available load balancing functionalities to your Cloud Foundry traffic. 

The HAProxy instances will be setup behind the [Azure Load Balancer](https://azure.microsoft.com/en-us/documentation/articles/load-balancer-overview/), which is a Layer 4 (TCP, UDP) load balancer that distributes incoming traffic among healthy service instances. To provide redundancy, we also recommend that you group two or more HAproxy instances in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/).

Please note that this guidance focuses on CF deployment. You need to follow the [guidance](../../guidance.md) to prepare the Azure environment and deploy BOSH first via ARM template. After you complete the section `Deploy BOSH`, you can follow this guidance for the rest Cloud Foundry deployment.

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

Create an Azure Load Balancer named `haproxylb` using the [script](./create-load-balancer.sh).

Please update the value which starts with `REPLACE-ME` and run it after you [login Azure CLI](../../get-started/create-service-principal.md#verify-your-service-principal).

>**NOTE:** By default, Azure load balancer has an `idle timeout` setting of 4 minutes but the default timeout of HAProxy is 900 as 15 minutes, this would cause the problem of connection dropped. [#99](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/99). As a result, in the script the `idle timeout` is set to 15 minutes to match the default timeout in HAProxy.

## Deploy Cloud Foundry with multiple HAProxy instances

1. Log on to your dev-box.

2. Login to your BOSH director VM

  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin.
  ```

  _**Note:** If you have used `bosh logout`, you should use `bosh login admin admin` to log in._

3. Update the cloud foundry manifest `~/example_manifests/multiple-vm-cf.yml` to set the router instance number to 2 and add a new static private IP.

  ```
  - name: router_z1
  instances: 2
  resource_pool: resource_z1
  templates:
  - {name: gorouter, release: cf}
  - {name: metron_agent, release: cf}
  networks:
  - name: cf_private
    static_ips: [10.0.16.12, 10.0.16.22]
  properties:
    ...
  ```

4. Update the cloud foundry manifest `~/example_manifests/multiple-vm-cf.yml` to add a new resource pool for HAProxy. If you do not use `haproxylb`, you need use your Azure Load Balancer name.

  ```
  resource_pools:
  ...
  - name: resource_haproxy
    network: cf_private
    stemcell:
      name: bosh-azure-hyperv-ubuntu-trusty-go_agent
      version: latest
    cloud_properties:
      load_balancer: haproxylb
      availability_set: haproxy
      instance_type: Standard_D1
    env:
      bosh:
        password: $6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0
  ```

5. Update the cloud foundry manifest `~/example_manifests/multiple-vm-cf.yml` to set the HAProxy instance number to 2, add a new static private IP for the second HAProxy instance, remove the `cf_public` network and add the IP address of the second router.

  ```
  - name: ha_proxy_z1
  instances: 2
  resource_pool: resource_haproxy
  templates:
  - {name: haproxy, release: cf}
  - {name: metron_agent, release: cf}
  - {name: consul_agent, release: cf}
  networks:
  - name: cf_private
    default: [gateway, dns]
    static_ips: [10.0.16.4, 10.0.16.5]
  properties:
    ...
    router:
      servers:
        z1: [10.0.16.12, 10.0.16.22]
    ...
  ```

6. Deploy cloud foundry

  ```
  ./deploy_cloudfoundry.sh ~/example_manifests/multiple-vm-cf.yml
  ```
