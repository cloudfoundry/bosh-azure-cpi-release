# Standard SKU Load Balancer

Standard SKU Load Balancer is recommended for Cloud Foundry deployment. Please review [Load Balancer SKU comparison](https://docs.microsoft.com/en-us/azure/load-balancer/skus) before you continue.

## Pre-requisites

* Login Azure CLI

    ```
    AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
    AZURE_TENANT_ID="<your-tenant-id>"
    AZURE_CLIENT_ID="<your-client-id>"
    AZURE_CLIENT_SECRET="<your-client-secret>"
    az login --service-principal --tenant ${AZURE_TENANT_ID} -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET}
    az account set -s ${AZURE_SUBSCRIPTION_ID}
    ```

## Create Standard SKU Load Balancers for cf-deployment

```
rg_name="<your-resource-group-name>"
lb_name="<your-standard-load-balancer-name>"
lb_ip_name="<your-public-ip-address-name-for-standard-load-balancer>"
az group deployment create -g ${rg_name} --template-file <template-file> --parameters loadBalancerName=${lb_name} loadBalancerPublicIPAddressName=${lb_ip_name}
```

* Create a load balancer for `router`

    ```
    az group deployment create -g ${rg_name} --template-file load-balancer-for-routers.json --parameters loadBalancerName=${lb_name} loadBalancerPublicIPAddressName=${lb_ip_name}
    ```

* Create a load balancer for `tcp router`

    ```
    az group deployment create -g ${rg_name} --template-file load-balancer-for-tcp-routers.json --parameters loadBalancerName=${lb_name} loadBalancerPublicIPAddressName=${lb_ip_name}
    for port in `seq 1024 1123`;
    do
      az network lb rule create --lb-name ${lb_name} --resource-group ${rg_name} --name "tcp-rule-$port" --protocol Tcp --frontend-port $port --backend-port $port --backend-pool-name BackendPool --probe-name healthProbe
    done
    ```

    By default, cf-deployment reserves TCP ports `1024-1123`. You can add more load balancing rules for other TCP ports if needed.

* Create a load balancer for `diego brain`

    ```
    az group deployment create -g ${rg_name} --template-file load-balancer-for-diego-brain.json --parameters loadBalancerName=${lb_name} loadBalancerPublicIPAddressName=${lb_ip_name}
    ```

* Create a load balancer for `mysql proxy`

    ```
    az group deployment create -g ${rg_name} --template-file load-balancer-for-mysql-proxy.json --parameters loadBalancerName=${lb_name} loadBalancerPublicIPAddressName=${lb_ip_name}
    ```

## Outbound connections

There are multiple outbound scenarios. Review the [doc](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-connections) carefully to understand the capabilities, constraints, and patterns as they apply to your deployment model and application scenario.

[Standard SKU SNAT programming](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-connections#preallocatedports) is per IP transport protocol and derived from the load balancing rule. If only a TCP load balancing rule exists, SNAT is only available for TCP. If you have only a TCP load balancing rule and need outbound SNAT for UDP, create a UDP load balancing rule from the same frontend to the same backend pool. This will trigger SNAT programming for UDP. A working rule or health probe is not required. Basic SKU SNAT always programs SNAT for both IP transport protocol, irrespective of the transport protocol specified in the load balancing rule.

For example, the BOSH agent of Ubuntu Xenial stemcell tries to sync time with NTP servers, which needs to use UDP port 123. You need to create a load balancing rule for any UDP port (e.g. `123`) to trigger SNAT programming for UDP.
