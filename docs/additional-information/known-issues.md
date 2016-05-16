# Known Issues

1. The deployment of Cloud Foundry fails because of timeout when creating VMs

  1. This could be due to network glitch, which would be resolved through a retry.

    ```
    bosh -n deploy
    ```

    If this deployment succeeds, then you can skip the next step.

  2. If the above re-deployment failed again, please follow the below steps, keep the unreachable VMs for the further investigation, and file an issue [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues).

    1. Delete your current Cloud Foundry deployment.

      ```
      bosh deployments # Get the name of the Cloud Foundry deployment
      bosh delete deployment CLOUD-FOUNDRY-DEPLOYMENT-NAME
      ```

    2. Delete your current BOSH deployment.

      ```
      bosh-init delete ~/bosh.yml
      ```

    3. Update `~/bosh.yml` if the debug option is not enabled.

      ```
      director:
        address: 127.0.0.1
        name: bosh
        db: *db
        cpi_job: cpi
        enable_snapshots: true
        debug:
          keep_unreachable_vms: true
      ```

    4. Re-deploy BOSH.

      ```
      bosh-init deploy ~/bosh.yml
      ```

    5. Re-deploy Cloud Foundry.

      ```
      bosh deployment PATH-TO-YOUR-MANIFEST-FOR-CLOUD-FOUNDRY
      bosh -n deploy
      ```

    6. If the deployment failed, the unreachable VMs will be kept for further investigations.

2. Connection dropped

  By default, Azure load balancer has an `idle timeout` setting of 4 minutes but the default timeout of HAProxy is 900 as 15 minutes, this would cause the problem of connection dropped. [#99](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/99)

  The timeout values of Azure load balancer and HAProxy need to be matched. There are two options:

  * Change the timeout of Azure Load Balancer to match HAProxy

    You can change the load balancer behavior to allow a [longer timeout setting for Azure load balancer](https://azure.microsoft.com/en-us/documentation/articles/load-balancer-tcp-idle-timeout/).

    Here is an example to change the timeout of Azure Load Balancer:

    ```
    azure network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruletcp$tcpPort" --protocol tcp --frontend-port $tcpPort --backend-port $tcpPort --frontend-ip-name $frontendIPName --backend-address-pool-name $backendPoolName --idle-timeout 15
    ```

  * Change the timeout of HAProxy to match Azure Load Balancer

    You can change the default timeout of HAProxy in the manifest as bellows.

    ```
    request_timeout_in_seconds: 180
    ```
