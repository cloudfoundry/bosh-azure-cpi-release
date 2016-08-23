# Deploy multiple HAProxy instances behind Azure Load Balancer

## Overview

This guidance describes how to setup multiple HAProxy instances for Cloud Foundry. Compared to a single instance of HAProxy, multiple HAProxy instances provide high-available load balancing functionalities to your Cloud Foundry traffic. 

The HAProxy instances will be setup behind the [Azure Load Balancer](https://azure.microsoft.com/en-us/documentation/articles/load-balancer-overview/), which is a Layer 4 (TCP, UDP) load balancer that distributes incoming traffic among healthy service instances. To provide redundancy, we also recommend that you group two or more HAproxy instances in an [Availability Set](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-manage-availability/).

Please note that this guidance focuses on CF deployment. You need to follow the [guidance](../../guidance.md) to prepare the Azure environment and deploy BOSH first via ARM template. After you complete the section `Deploy BOSH`, you can follow this guidance for the rest Cloud Foundry deployment.

Below is a sample deployment, which you can adjust based on your workload and performance requirements. It is a multiple-VM Cloud Foundry with 2 HAProxy instances.

  ```
  +---------------------------------------------------------------------------+---------+-----+------------------+-------------+
  | VM                                                                        | State   | AZ  | VM Type          | IPs         |
  +---------------------------------------------------------------------------+---------+-----+------------------+-------------+
  | access_z1/0 (ab536515-3c7f-4c08-a321-c4b567926a8e)                        | running | n/a | resource_z1      | 10.0.16.110 |
  | api_z1/0 (7ba0fa0d-db17-4844-a79c-3fa5a715b1bc)                           | running | n/a | resource_z1      | 10.0.16.102 |
  | brain_z1/0 (5923d5f8-6b64-4659-af59-9a96a8232a65)                         | running | n/a | resource_z1      | 10.0.16.106 |
  | cc_bridge_z1/0 (01321f22-a44f-450a-b509-4de140fc45e5)                     | running | n/a | resource_z1      | 10.0.16.109 |
  | cell_z1/0 (d518d00d-b8c8-480a-93b9-c99b6799f668)                          | running | n/a | resource_z1      | 10.0.16.107 |
  | cell_z1/1 (0cf93ce5-eb9b-4e91-9703-e286961508ee)                          | running | n/a | resource_z1      | 10.0.16.108 |
  | consul_z1/0 (ea8c1b78-1fed-47c1-b6fa-0693ac8445ec)                        | running | n/a | resource_z1      | 10.0.16.16  |
  | database_z1/0 (7dc46349-a8ea-4619-bb44-00e525160fc1)                      | running | n/a | resource_z1      | 10.0.16.105 |
  | doppler_z1/0 (ac5c4097-71ce-4d28-bf99-3287e665047b)                       | running | n/a | resource_z1      | 10.0.16.103 |
  | etcd_z1/0 (51fa4ec2-cde4-4e49-bd92-de1a27823b1a)                          | running | n/a | resource_z1      | 10.0.16.14  |
  | ha_proxy_z1/0 (44d728d9-ff4d-4bee-b89e-21d40abfe0fb)                      | running | n/a | resource_haproxy | 10.0.16.4   |
  | ha_proxy_z1/1 (0565f4a3-37f0-42cf-9ef0-5332f067027c)                      | running | n/a | resource_haproxy | 10.0.16.5   |
  | loggregator_trafficcontroller_z1/0 (941ffc66-e681-4bec-b691-6d36371d4eba) | running | n/a | resource_z1      | 10.0.16.104 |
  | nats_z1/0 (b288ef95-7e37-414b-ab58-5e9d5e05aa65)                          | running | n/a | resource_z1      | 10.0.16.13  |
  | nfs_z1/0 (81733add-df1b-43cf-8274-62e4ab23ca42)                           | running | n/a | resource_z1      | 10.0.16.15  |
  | postgres_z1/0 (b2bbd940-f42d-443b-b86a-75925e08747e)                      | running | n/a | resource_z1      | 10.0.16.11  |
  | route_emitter_z1/0 (e00d21be-003a-4f8c-9bb1-9fb4e250e712)                 | running | n/a | resource_z1      | 10.0.16.111 |
  | router_z1/0 (f6a72ce7-94bb-4272-a3e8-a0b4fdbbf959)                        | running | n/a | resource_z1      | 10.0.16.12  |
  | router_z1/1 (897c5bc0-9e76-4c78-8696-012c29147221)                        | running | n/a | resource_z1      | 10.0.16.22  |
  | uaa_z1/0 (c5a727c1-8611-4281-8f09-41c79362e263)                           | running | n/a | resource_z1      | 10.0.16.101 |
  +---------------------------------------------------------------------------+---------+-----+------------------+-------------+
  ```

## Create Azure Load Balancer

Create an Azure Load Balancer named `haproxylb` using the [script](./create-load-balancer.sh).

Please update the value which starts with `REPLACE-ME` and run it after you [login Azure CLI](../../get-started/create-service-principal.md#verify-your-service-principal).

>**NOTE:** By default, Azure load balancer has an `idle timeout` setting of 4 minutes but the default timeout of HAProxy is 900 as 15 minutes, this would cause the problem of connection dropped. [#99](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/99). As a result, in the script the `idle timeout` is set to 15 minutes to match the default timeout in HAProxy.

## Deploy Cloud Foundry with multiple HAProxy instances

1. Log on to your dev-box.

2. Login to your BOSH director VM

  ```
  bosh target 10.0.0.4
  ```

  >**Note:** The username and password can be found in your `bosh.yml`. If you deployed BOSH using ARM template, the default username is `admin`, and the password can be found in the file `~/BOSH_DIRECTOR_ADMIN_PASSWORD`.

3. Update the cloud foundry manifest `~/example_manifests/multiple-vm-cf.yml`.

  1. Update the job `router_z1`

    1. Set the router instance number to 2

    2. Add a new static private IP

    Example:

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

  2. Update the job `ha_proxy_z1`

    1. Add a new resource pool for HAProxy. If you do not use `haproxylb`, you need use your Azure Load Balancer name.

    2. Set the HAProxy instance number to 2

    3. Use the resource pool `resource_haproxy`

    4. Remove the `cf_public` network

    5. Add a new static private IP for the second HAProxy instance

    6. Add the IP address of the second router

    Example:

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
        security_group: nsg-cf
    ...
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
        - 10.0.16.12
        - 10.0.16.22
      ...
    ```

4. Deploy cloud foundry

  ```
  ./deploy_cloudfoundry.sh ~/example_manifests/multiple-vm-cf.yml
  ```
