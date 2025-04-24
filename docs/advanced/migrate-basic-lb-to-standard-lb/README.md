# Migrate Basic SKU Load Balancer to Standard SKU Load Balancer

[Standard Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview) is a new Load Balancer product for all TCP and UDP applications with an expanded and more granular feature set over Basic Load Balancer. Azure Standard Load Balancer enables you to scale your applications and create high availability from small scale deployments to large and complex multi-zone architectures. While Basic Load Balancer exists within the scope of an availability set, a Standard Load Balancer is fully integrated with the scope of a virtual network. For Cloud Foundry, this is required if you integrate with Azure Availability Zone. In addition, it ensures Bosh can create VMs across Availability Sets successfully for scenarios like VM resizing, and automatic VM type selection.

Besides the benefits coming with Standard LB, we recommend you to migrate to standard load balancer for better CF VM type switching experience, and in prepare for the Azure Availabity Zone. This document guides you through the steps for the migration.

Note when planning the migration, you need to be aware of following [requirements](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview#migration-between-skus).

* Matching SKUs must be used for Load Balancer and Public IP resources. You can't have a mixture of Basic SKU resources and Standard SKU resources. It means that, when you migrate your load balancers from `Basic SKU` to `Standard SKU`, you will need a new public IP address, that can match the `Standard SKU`.

* You will need to remove the Basic SKU LB first, and then add Standard SKU LB, as VMs can'be be attached to both SKUs simultaneously.

The above requirements may cause downtime before the DNS propagations are finished globally. In this guidance, we will create additional HAProxy temporally to avoid the system downtime.

## Summary

This guidance assumes you have created 4 load balancers (`Router`, `TCP Router`, `Diego Brain` and `MySQL Proxy`), although each can be migrated independently. You can migrate these load balancers sequentially or at the same time.

* For the load balancers of `Router`, `TCP Router` and `Diego Brain`:

    * Switching traffic from `router/tcp-router/diego-brain` to `HAProxy`. The `HAProxy` instances also terminates HTTP/HTTPS traffic for applications and forwards the Diego brain port (2222) and TCP router ports (1024-1123 by default). You could create a new load balancer and attach it to `HAProxy` instead of the `router/tcp-router/diego-brain`. This load balancer is a temparary LB, which can be deleted after migration.

    * Once DNS is propagated, you can delete the old basic load balancers of `router/tcp-router/diego-brain`.

    * Switching traffic from `HAProxy` to `router/tcp-router/diego-brain`. You could create a 2nd new load balancer (Standard SKU) and attach it to the `router/tcp-router/diego-brain`. Make sure that DNS is propagated.

* For the load balancer of `MySQL Proxy`:

    The LB of `MySQL Proxy` is an internal LB. No DNS records need to be updated. After removing the Basic SKU load balancer, the Cloud Foundry components can still connect to MySQL servers via `sql-db.service.cf.internal` instead of `mysql.<your-domain>`. So, we can simply remove the Basic SKU load balancer and add the Standard SKU load balancer. There may be a minor switching time when we switch from Basic to standard LB.

## Migrate Load Balancers in cf-deployment

In the following steps, we assume you are not using PAS, you can modify the bosh manifest directly. `Router`, `TCP Routers` and `Diego Brain` (also called `scheduler` in `cf-deployment`) have their own basic load balancers. But `MySQL Proxy` (also called `database` in `cf-deployment`) doesn't have the load balancer.

### Pre-requisites

* You have an existing [cf-deployment](https://github.com/cloudfoundry/cf-deployment).

* Basic SKU Load Balancers are used in your deployment.

* You need to horizontally scale most Cloud Foundry components to multiple instances to achieve the redundancy required for high availability. Otherwise, there will be downtime during migration. Don't use the ops [scale-to-one-az.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/scale-to-one-az.yml).

* You need to create multiple standard load balancers: one for HAProxy instance, and one for `Router`, `TCP Router` and `Diego Brain` respectively.

    * You can follow the [doc](../standard-load-balancer) to create [Standard SKU public IP address](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-public-ip-address) and a [Standard SKU load balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview). Please note down the load balancer name and the public IP address.

    * Please make sure all the configurations (e.g. backend pool, health probes and load balancing rules) are same to the basic LBs.

* In your DNS provider, the records of your domain should be:

    * `*.<your-domain>` is resolved to the public IP address of `Router` load balancer.

    * `tcp.<your-domain>` is resolved to the public IP address of `TCP Router` load balancer.

    * `ssh.<your-domain>` is resolved to the public IP address of `Diego Brain` load balancer.

### Steps

1. Create a load balancer for HAProxy instances using the [template](../standard-load-balancers/load-balancer-for-haproxy.json). Please check the load balancer rules carefully, and add rules if it does not exist in the template. The LB will be used in the next step.

1. Add an HAProxy instance with a LB if there are no HAProxy instances in your deployment originally. **Deploy!**

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

1. Verify whether the deployment with the HAProxy instance works. You need to login CF in two places. In the first place, the domain is still resovled to the public IP address of Basic SKU load balancer. In the second place, the domain is resolved to the public IP address of `HAProxy` load balancer. If the deployment works well, continue next steps.

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

    * `*.<your-domain>` is resolved to the new public IP address of `Router` load balancer (Standard SKU).

    * `tcp.<your-domain>` is resolved to the new public IP address of `TCP Router` load balancer (Standard SKU).

    * `ssh.<your-domain>` is resolved to the new public IP address of `Diego Brain` load balancer (Standard SKU).

1. Verify whether the new Standard SKU LBs work. You need to login CF in two places. In the first place, the domain is still resovled to the public IP address of `HAProxy` load balancer. In the second place, the domain is resolved to the public IP address of Standard SKU load balancer. If the deployment works well, continue next steps.

1. Remove the HAProxy instances from your deployment. **Deploy!**
