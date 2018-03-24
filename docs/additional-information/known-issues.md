# Known Issues

1. Connection dropped

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

        ```YAML
        request_timeout_in_seconds: 180
        ```

1. Limits of Premium Storage blob snapshots

    The BOSH snapshot operation may be throttled if you do all of the following:

    * Use Premium Storage for the Cloud Foundry VMs.

    * Enable snapshot in `bosh.yml`. For more information on BOSH Snapshots, please go to https://bosh.io/docs/snapshots.html.

        ```YAML
        director:
          enable_snapshots: true
        ```

    * The time between consecutive snapshots by BOSH is less than **10 minutes**. The limits are documented in [Snapshots and Copy Blob for Premium Storage](https://azure.microsoft.com/en-us/documentation/articles/storage-premium-storage/#snapshots-and-copy-blob). 

    The workaround is:

    * Disable snapshot temporarily.

        ```YAML
        director:
          enable_snapshots: false
        ```

    * Adjust the snapshot interval to more than 10 minutes.

1. Version mismatch between CPI and Stemcell

    For CPI v11 or later, the compatible stemcell version is v3181 or later. If the stemcell version is older than v3181, you may hit the following failure when deploying BOSH.

    ```
    Command 'deploy' failed:
      Deploying:
        Creating instance 'bosh/0':
          Waiting until instance is ready:
            Sending ping to the agent:
              Performing request to agent endpoint 'https://mbus-user:mbus-password@10.0.0.4:6868/agent':
                Performing POST request:
                  Post https://mbus-user:mbus-password@10.0.0.4:6868/agent: dial tcp 10.0.0.4:6868: getsockopt: connection refused
    ```

    It is recommended to use the latest version. For example, Stemcell v3232.5 or later, and CPI v12 or later. You may hit the issue [#135](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/135) if you still use an older stemcell than v3232.5.

1. Invalid or expired service principal

    ```
    http_get_response - get_token - http error: 400
    ```

    Service principal is most likely invalid. Verify that client ID, client secret and tenant ID successfully work with the [steps](../get-started/create-service-principal.md#verify-your-service-principal).

    If your service principal worked and you get the above error suddenly, it may be caused by that your service principal expired. You need to go to Azure Portal to update client secret. By default, the service principal will expire in one year.

    1. Go to [Azure Portal](https://manage.windowsazure.com/), select `active directory` -- > ORGANIZATION-NAME -- > `Applications` -- > search your service principal name.

    ![Service Principal on Azure Portal](./service-principal-on-portal.png)

    1. Then choose your service principal, select `Configure` -- > `keys` -- > add a new key.

    ![Add the Client Secret](./add-client-secret.png)

1. `attach_disk_to_virtual_machine - cannot find an available lun in the virtual machine`

    When CPI requests an additional data disk that exceeds the max data disks, CPI throws this error. Please reference [the max data disks per VM size](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/sizes-general).

    The error mainly happens in the following scenario:

    In BOSH, disk "resizing" means attaching a new disk with the requested size to the VM, migrating the data from the old disk to the new one and detaching the old disk. This requires that you always need an extra LUN for resizing request. If you already used up all your LUNs, a disk resizing request to BOSH will trigger this error. For example, the max data disks of the VM size `Standard_D1` is `2`, if you already used one as ephemeral disk, another one for persistent disk, then you might hit this error when you upgrade CF with a bigger disk size.  

    It is recommended that you always leave room for an extra disk for resizing purpose. If the VM size can only have two data disks, please avoid using a data disk as the ephemeral disk. In case you cannot have additional data disk, follow below steps to workaround this issue:

    1. Upgrade the [`instance_type`](https://bosh.io/docs/azure-cpi.html#resource-pools) to a bigger VM size. For example, from `Standard_D1` to `Standard_D2`. Then run `bosh deploy`.

       ```YAML
       resource_pools:
         - name: default
           network: default
           stemcell:
             name: bosh-azure-hyperv-ubuntu-trusty-go_agent
             version: latest
           cloud_properties:
             instance_type: Standard_D2
       ```

    1. Increase the data disk size in the manifest. Then run `bosh deploy`.

    1. (Optional) Downgrade the `instance_type` to the original VM size if you want. Then run `bosh deploy`.

1. Hanging VMs with BOSH Persistent Disks

    Cloud Foundry deployment might fail occasionally during data disk attaching. This only happens when you set `use_root_disk` to `true` in `vm_type` for the VM so it does not have a dedicated ephemeral disk.

    This is a platform bug, you will see error message like `Timed out sending 'list_disk' to ...` when updating an instance. You will also notice that the VM cannot response and the deploment will fail finally.

    Error example:
    ```
    Started updating instance mysql
    Started updating instance mysql > mysql/33e8e561-233c-4a26-9f7e-4a6fbf978ce4 (0) (canary). Failed: Timed out sending 'list_disk' to c4e6e2ff-8ee2-463b-a1d2-f1190b4e21e1 after 45 seconds (00:18:15)
   
    Error 450002: Timed out sending 'list_disk' to c4e6e2ff-8ee2-463b-a1d2-f1190b4e21e1 after 45 seconds
    ```

    A workaround has been included in Azure CPI [v33](https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-azure-cpi-release?v=33) to mitigate the issue. Since January, 2018, the issue was fixed on Azure, but the workaround will be kept for while until the fix is fully tested.
