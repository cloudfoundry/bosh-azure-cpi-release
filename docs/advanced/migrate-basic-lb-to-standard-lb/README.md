# Migrate Basic SKU Load Balancer to Standard SKU Load Balancer

[Standard Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview) is a new Load Balancer product for all TCP and UDP applications with an expanded and more granular feature set over Basic Load Balancer.

Matching SKUs must be used for Load Balancer and Public IP resources. You can't have a mixture of Basic SKU resources and Standard SKU resources. You can't attach standalone virtual machines, virtual machines in an availability set resource, or a virtual machine scale set resources to both SKUs simultaneously.

Due to these limits, the IP address of the Cloud Foundry API endpoint will **CHANGE** when you migrate from Basic to Standard SKU, which may cause downtime before the DNS propagations are finished globally. This guidance can help to reduce the downtime to zero by adding another instance group `router2`. The instances in `router2` are associated with the Standard SKU Load Balancer and Public IP. During migrating, both the old and new routers work together. After migration, the old routers can be removed safely.

In addition, this guidance works no matter you use availability zones or availability sets.

## Pre-requisites

You have an existing CF deployment which is deployed with availability sets and Basic SKU LB. There are multiple routers in the availability set. You can either refer to this [ARM template](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) or [cf-deployment](https://github.com/cloudfoundry/cf-deployment) to get a CF deployment manifest.

## Create Standard SKU Load Balancer

Follow the [doc](../availability-zone/README.md#create-standard-sku-load-balancer) to create [Standard SKU public IP address](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-public-ip-address) and a [Standard SKU load balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-overview). Please note down the load balancer name and the public IP address in the output.

## Migration Steps

1. Update `vm_extensions` of your cloud config by adding the following contents in `example_manifests/cloud-config.yml`.
 
    ```
    - name: cf-router2-network-properties
      cloud_properties:
        load_balancer: <your-standard-load-balancer-name>
    ```
 
1. Use the ops file [add-new-router.yml](./add-new-router.yml) to add a instance group `router2` and update the existing instance group `router` and `uaa` in `cf-deployment.yml`. You can check the below difference.

    ```diff
     - name: uaa
       azs:
       - z1
       - z2
       instances: 2
       vm_type: minimal
       stemcell: default
       networks:
       - name: default
       jobs:
       - name: consul_agent
         release: consul
         consumes:
           consul_common: {from: consul_common_link}
           consul_server: nil
           consul_client: {from: consul_client_link}
         properties:
           consul:
             agent:
               services:
                 uaa: {}
       - name: uaa
         release: uaa
    +    consumes:
    +      router: {from: gorouter2}
         properties:
           login:
             saml:
               activeKeyId: key-1
     - name: router
       azs:
       - z1
       - z2
       instances: 2
       vm_type: minimal
       vm_extensions:
       - cf-router-network-properties
       stemcell: default
       update:
         serial: true
       networks:
       - name: default
       jobs:
       - name: consul_agent
         release: consul
         consumes:
           consul_common: {from: consul_common_link}
           consul_server: nil
           consul_client: {from: consul_client_link}
         properties:
           consul:
             agent:
               services:
                 gorouter: {}
       - name: gorouter
         release: routing
    +    provides:
    +      gorouter: { as: gorouter1 }
         properties:
           router:
             enable_ssl: true
             tls_pem:
             - cert_chain: "((router_ssl.certificate))"
               private_key: "((router_ssl.private_key))"
             status:
               password: "((router_status_password))"
               user: router-status
             route_services_secret: "((router_route_services_secret))"
             tracing:
               enable_zipkin: true
           routing_api:
             enabled: true
           uaa:
             clients:
               gorouter:
                 secret: "((uaa_clients_gorouter_secret))"
             ca_cert: "((uaa_ca.certificate))"
             ssl:
               port: 8443
    +- name: router2
    +  azs:
    +  - z1
    +  - z2
    +  instances: 2
    +  vm_type: minimal
    +  vm_extensions:
    +  - cf-router2-network-properties
    +  stemcell: default
    +  update:
    +    serial: true
    +  networks:
    +  - name: default
    +  jobs:
    +  - name: consul_agent
    +    release: consul
    +    consumes:
    +      consul_common: {from: consul_common_link}
    +      consul_server: nil
    +      consul_client: {from: consul_client_link}
    +    properties:
    +      consul:
    +        agent:
    +          services:
    +            gorouter: {}
    +  - name: gorouter
    +    release: routing
    +    provides:
    +      gorouter: { as: gorouter2 }
    +    properties:
    +      router:
    +        enable_ssl: true
    +        tls_pem:
    +        - cert_chain: "((router_ssl.certificate))"
    +          private_key: "((router_ssl.private_key))"
    +        status:
    +          password: "((router_status_password))"
    +          user: router-status
    +        route_services_secret: "((router_route_services_secret))"
    +        tracing:
    +          enable_zipkin: true
    +      routing_api:
    +        enabled: true
    +      uaa:
    +        clients:
    +          gorouter:
    +            secret: "((uaa_clients_gorouter_secret))"
    +        ca_cert: "((uaa_ca.certificate))"
    +        ssl:
    +          port: 8443
    ```

1. Deploy your Cloud Foundry.

1. Resolve your system domain to the public IP address of the standard SKU load balancer.

1. After DNS propagations are done, you can use the ops file [remove-old-router.yml](./remove-old-router.yml) to remove the instance group `router`.
