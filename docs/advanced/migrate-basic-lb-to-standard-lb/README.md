# Migrate Basic SKU Load Balancer to Standard SKU Load Balancer

[Standard Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview) is a new Load Balancer product for all TCP and UDP applications with an expanded and more granular feature set over Basic Load Balancer.

Note when planning the migration, you need to be aware of following restrictions.

* Matching SKUs must be used for Load Balancer and Public IP resources. You can't have a mixture of Basic SKU resources and Standard SKU resources. It means that, when you migrate your load balancers from `Basic SKU` to `Standard SKU`, you have to use the Standard SKU Public IP and the IP address will **CHANGE**.

* You can't attach standalone virtual machines, virtual machines in an availability set resource, or a virtual machine scale set resources to both SKUs simultaneously. You have to remove the Basic SKU load balancers first and then add the Standard SKU load balancers. You can't switch the load balancer in **ONE** step.

The above [limits](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview#migration-between-skus) may cause downtime before the DNS propagations are finished globally. This guidance can help to reduce the downtime.

## How to Migrate

This guidance assumes you have created 4 load balancers (`Router`, `TCP Router`, `Diego Brain` and `MySQL Proxy`), although each can be migrated independently. This section briefly describes how to migrate load balancers. For detailed steps, you can follow the sections [Migrate Load Balancers in cf-deployment](#migrate-load-balancers-in-cf-deployment) and [Migrate Load Balancers in Pivotal Application Service](#migrate-load-balancers-in-pivotal-application-service).

* For the load balancers of `Router`, `TCP Router` and `Diego Brain`:

    * Switching traffic from `router/tcp-router/diego-brain` to `HAProxy`. The `HAProxy` instances also terminates HTTP/HTTPS traffic for applications and forwards the Diego brain port (2222) and TCP router ports (1024-1123 by default). You could make a new load balancer and attach it to `HAProxy` instead of the `router/tcp-router/diego-brain`.

    * Once DNS is propagated, you can delete the old basic load balancers of `router/tcp-router/diego-brain`.

    * Repeat the process with a 2nd new load balancer to move the traffic back to `router/tcp-router/diego-brain`.

* For the load balancer of `MySQL Proxy`:

    After removing the Basic SKU load balancer, the Cloud Foundry components can still connect to MySQL servers via `sql-db.service.cf.internal` instead of `mysql.<your-domain>`. So, we can simply remove the Basic SKU load balancer and add the Standard SKU load balancer.

## Migrate Load Balancers in cf-deployment

In the following steps, we assume that there are no HAProxy instances in your deployment originally. `Router`, `TCP Routers` and `Diego Brain` (also called `scheduler` in `cf-deployment`) have their own basic load balancers. But `MySQL Proxy` (also called `database` in `cf-deployment`) doesn't have the load balancer.

### Pre-requisites

* You have an existing [cf-deployment](https://github.com/cloudfoundry/cf-deployment). You can refer to the [ARM template](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md).

* You deployment MUST have high availability. Otherwise, there will be downtime during migration. Please use the ops file [use-azure-storage-blobstore.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/use-azure-storage-blobstore.yml) and [scale-database-cluster.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/scale-database-cluster.yml). Don't use the ops [scale-to-one-az.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/scale-to-one-az.yml).

* Basic SKU Load Balancers are used in your deployment.

* You need to create the standard load balancers. Please make sure all the configurations (e.g. backend pool, health probes and load balancing rules) are same to the basic LBs.

    * You can follow the [doc](../standard-load-balancer) to create [Standard SKU public IP address](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-public-ip-address) and a [Standard SKU load balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview). Please note down the load balancer name and the public IP address.

* In your DNS provider, the records of your domain should be:

    * `*.<your-domain>` is resolved to the public IP address of `Router` load balancer.

    * `tcp.<your-domain>` is resolved to the public IP address of `TCP Router` load balancer.

    * `ssh.<your-domain>` is resolved to the public IP address of `Diego Brain` load balancer.

### Steps

1. Create a load balancer for HAProxy instances using the [template](../standard-load-balancers/load-balancer-for-haproxy.json). Please check the load balancer rules carefully, and add rules if it does not exist in the template. The LB will be used in the next step.

1. Add an HAProxy instance with a LB to your deployment. **Deploy!**

    * Use the ops file [use-haproxy.yml](./use-haproxy.yml) when deploying Cloud Foundry. This ops file adds an HAProxy instance into your deployment. It doesn't remove the load balancers of `Router`, `TCP Router` and `Diego Brain`.

        ```
        bosh -d cf deploy cf-deployment.yml \
          ...
          -o use-haproxy.yml \
          ...
        ```

    * This ops file also requires your BOSH cloud-config to have a `vm_extension` called `cf-haproxy-network-properties`, which configures load balancer and network security group.

      * The load balancer should have rules for at least the default HTTP and HTTPS ports (80 and 443), port 2222 for diego brain, as well as [the port range configured for the TCP Routing](https://github.com/cloudfoundry/cf-deployment/blob/a6983a1b3345cd9f5af0f26d5c10265de0c7851f/cf-deployment.yml#L726).

      * The network security group should allow public traffic on the necessary ports. You will need to allow at least the default HTTP and HTTPS ports (80 and 443), port 2222 for diego brain, as well as [the port range configured for the TCP Routing](https://github.com/cloudfoundry/cf-deployment/blob/a6983a1b3345cd9f5af0f26d5c10265de0c7851f/cf-deployment.yml#L726).

1. Navigate to your DNS provider, and create entries for the following domains.

    * `*.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

    * `tcp.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

    * `ssh.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

1. Remove the Basic SKU load balancer in `cf-router-network-properties`, `cf-tcp-router-network-properties` and `diego-ssh-proxy-network-properties`. **Deploy!**

    ```diff
      vm_extensions:
      - name: cf-router-network-properties
    -   cloud_properties:
    -     load_balancer: <basic-lb-for-router>
      - name: cf-tcp-router-network-properties
    -   cloud_properties:
    -     load_balancer: <basic-lb-for-tcp-router>
      - name: diego-ssh-proxy-network-properties
    -   cloud_properties:
    -     load_balancer: <basic-lb-for-diego-brain>
    ```

1. Add the Standard SKU load balancer in `cf-router-network-properties`, `cf-tcp-router-network-properties` and `diego-ssh-proxy-network-properties`. **Deploy!**

    ```diff
      vm_extensions:
      - name: cf-router-network-properties
    +   cloud_properties:
    +     load_balancer: <standard-lb-for-router>
      - name: cf-tcp-router-network-properties
    +   cloud_properties:
    +     load_balancer: <standard-lb-for-tcp-router>
      - name: diego-ssh-proxy-network-properties
    +   cloud_properties:
    +     load_balancer: <standard-lb-for-diego-brain>
    ```


1. Navigate to your DNS provider, and create entries for the following domains. Wait until DNS propagations are finished globally.

    * `*.<your-domain>` is resolved to the new public IP address of Router load balancer (Standard SKU).

    * `tcp.<your-domain>` is resolved to the new public IP address of TCP Router load balancer (Standard SKU).

    * `ssh.<your-domain>` is resolved to the new public IP address of Diego Brain load balancer (Standard SKU).

1. Remove the HAProxy instances from your deployment. **Deploy!**

## Migrate Load Balancers in Pivotal Application Service

In the following steps, we assume that there are no HAProxy instances in your deployment originally. `Router`, `TCP Routers`, `Diego Brain` and `MySQL Proxy` have their own basic load balancers.

### Pre-requisites

* You have an existing [Pivotal Cloud Foundry (PCF)](https://docs.pivotal.io/pivotalcf/2-1/customizing/azure.html). You can refer to the [document](https://docs.pivotal.io/pivotalcf/2-1/customizing/azure.html). Note: You should choose `Launching an BOSH Director Instance with an ARM Template` in the document.

* You deployment MUST have high availability. Otherwise, there will be downtime during migration. Please refer to [PCF high availability](https://docs.pivotal.io/pivotalcf/2-1/concepts/high-availability.html).

* Basic SKU Load Balancers are used in your deployment.

* You need to create the standard load balancers. Please make sure all the configurations (e.g. backend pool, health probes and load balancing rules) are same to the basic LBs.

    * You can follow the [doc](../standard-load-balancer) to create [Standard SKU public IP address](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-public-ip-address) and a [Standard SKU load balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview). Please note down the load balancer name and the public IP address.

* In your DNS provider, the records of your domain should be:

    * `*.apps.<your-domain>` is resolved to the public IP address of `Router` load balancer.

    * `*.system.<your-domain>` is resolved to the public IP address of `Router` load balancer.

    * `tcp.<your-domain>` is resolved to the public IP address of `TCP Router` load balancer.

    * `ssh.<your-domain>` is resolved to the public IP address of `Diego Brain` load balancer.

    * `mysql.<your-domain>` is resolved to the internal IP address of `MySQL Proxy` load balancer.

### Steps

1. Migrate the load balancers of `Router`, `TCP Routers` and `Diego Brain`.

    1. Create a load balancer for HAProxy instances using the [template](../standard-load-balancers/load-balancer-for-haproxy.json). The LB will be used in the next step.

    1. Add an HAProxy instance with a LB to your deployment. **Apply changes!**

        * Locate the **HAProxy** job in the **Resource Config** pane, select `2` in the field under **Instances**, and enter the name of your external LB in the field under **Load Balancers**.

        * The load balancer should have rules for at least the default HTTP and HTTPS ports (80 and 443), port 2222 for diego brain, as well as [the port range configured for the TCP Routing](https://github.com/cloudfoundry/cf-deployment/blob/a6983a1b3345cd9f5af0f26d5c10265de0c7851f/cf-deployment.yml#L726).

        * The network security group for the HAProxy instnaces should allow public traffic on the necessary ports. You will need to allow at least the default HTTP and HTTPS ports (80 and 443), port 2222 for diego brain, as well as [the port range configured for the TCP Routing](https://github.com/cloudfoundry/cf-deployment/blob/a6983a1b3345cd9f5af0f26d5c10265de0c7851f/cf-deployment.yml#L726).

    1. Navigate to your DNS provider, and create entries for the following domains.

        * `*.apps.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

        * `*.system.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

        * `tcp.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

        * `ssh.<your-domain>` is resolved to the public IP address of `HAProxy` load balancer.

    1. Remove the Basic SKU load balancer in the **Load Balancers** field of `Router`, `TCP Router` and `Diego Brain`. **Apply changes!**

    1. Add the Standard SKU load balancer in the **Load Balancers** field of `Router`, `TCP Router` and `Diego Brain`. **Apply changes!**

    1. Navigate to your DNS provider, and create entries for the following domains. Wait until DNS propagations are finished globally.

        * `*.apps.<your-domain>` is resolved to the new public IP address of `Router` load balancer (Standard SKU).

        * `*.system.<your-domain>` is resolved to the new public IP address of `Router` load balancer (Standard SKU).

        * `tcp.<your-domain>` is resolved to the new public IP address of `TCP Router` load balancer (Standard SKU).

        * `ssh.<your-domain>` is resolved to the new public IP address of `Diego Brain` load balancer (Standard SKU).

    1. Remove the HAProxy instances from your deployment. **Apply changes!**

1. Migrate the load balancer of `MySQL Proxy`.

    1. Remove `MySQL Service Hostname` in [`Step 12: (Optional) Configure Internal MySQL`](https://docs.pivotal.io/pivotalcf/2-1/customizing/azure-er-config.html#internal-mysql) and the Basic SKU load balancer in the **Load Balancers** field of `MySQL Proxy`. **Apply changes!**

    1. Configure `MySQL Service Hostname` in [`Step 12: (Optional) Configure Internal MySQL`](https://docs.pivotal.io/pivotalcf/2-1/customizing/azure-er-config.html#internal-mysql) and add the Standard SKU load balancer in the **Load Balancers** field of `MySQL Proxy`. **Apply changes!**

    1. Navigate to your DNS provider, and create entries for the following domains. Wait until DNS propagations are finished globally.

        * `mysql.<your-domain>` is resolved to the new IP address of `MySQL` load balancer (Standard SKU).
