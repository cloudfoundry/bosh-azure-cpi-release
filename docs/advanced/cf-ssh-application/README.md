# SSH into the application

## Prerequisites

* Follow the [guidance](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) to setup a Cloud Foundry deployment using a real domain.

    Change the variable `system_domain` to your domain in `deploy_cloud_foundry.sh`.

## Steps

1. Create a load balancer and a public IP using the [script](./create-load-balancer.sh).

    For exmaple, the load balancer is called `cf-ssh-lb`, and the public IP has an address `1.1.1.1`. In your domain provider, you need to resolve the domain `ssh.<YOUR-SYSTEM-DOMAIN>` to the IP address `1.1.1.1`.

1. Update the cloud config `example_manifests/cloud-config.yml`.

    ```
    - name: diego-ssh-proxy-network-properties
      cloud_properties:
        load_balancer: ((ssh_load_balancer_name))
    ```

1. Add the line `-v ssh_load_balancer_name=cf-ssh-lb` to the command `bosh -n update-cloud-config` in `deploy_cloud_foundry.sh`.

1. Run `./deploy_cloud_foundry.sh`.

1. Login Cloud Foundry, and ssh into your application using `cf ssh <app-name>`.
