# Troubleshooting

1. `api.<system-domain>: no such host`

    ```
    Error performing request: Get https://api.<system-domain>/v2/info: dial tcp: lookup api.<system-domain>: no such host
    ```

    If you hit the error when you try to login Cloud Foundry, you should check if your DNS is ready. You can prepare your own DNS and configure it properly.

1. Director could not be targeted after VM restart, see [#55](https://github.com/cloudfoundry/bosh-azure-cpi-release/issues/55)

1. Failed to deploy BOSH with `get_token` error, see [#49](https://github.com/cloudfoundry/bosh-azure-cpi-release/issues/49)

    You should verify whether the service principal is valid by [the steps](../get-started/create-service-principal.md#verify-your-service-principal).

1. Failed because the operation exceeds quota limits of Core.

    ```
    Error 100: http_put - error: 409 message: {
      "error": {
        "code": "OperationNotAllowed",
        "message": "Operation results in exceeding quota limits of Core. Maximum allowed: 4, Current in use: 4, Additional requested: 1."
      }
    }
    ```

    You can choose any of the following options:

        * Upgrade your subscription if you are using [a Free Trial](https://azure.microsoft.com/en-us/pricing/free-trial/).

        * Go to the portal and file a support issue to raise your quota.

        * Update your manifest to reduce the core number. For example, you can reduce the workers of `compilation` into 1. See [#57](https://github.com/cloudfoundry/bosh-azure-cpi-release/issues/57)

            ```YAML
            compilation:
              workers: 1
              network: cf_private
              reuse_compilation_vms: true
              cloud_properties:
                instance_type: Standard_D1
            ```

1. The deployment of Cloud Foundry fails because of timeout when creating VMs

    1. This could be due to network glitch, which would be resolved through a retry.

        ```
        bosh -n deploy
        ```

        If this deployment succeeds, then you can skip the next step.

    1. If the above re-deployment failed again, please follow the below steps, keep the unreachable VMs for the further investigation, and file an issue [**HERE**](https://github.com/cloudfoundry/bosh-azure-cpi-release/issues).

        1. Update `~/bosh.yml` if the debug option is not enabled.

            ```YAML
            director:
              debug:
                keep_unreachable_vms: true
              ...
            azure:
              keep_failed_vms: true
              ...
            ```

        1. Re-deploy BOSH.

            ```
            bosh-init deploy ~/bosh.yml
            ```

        1. Re-deploy Cloud Foundry.

            ```
            bosh deployment PATH-TO-YOUR-MANIFEST-FOR-CLOUD-FOUNDRY
            bosh -n deploy
            ```

        1. If the deployment failed, the unreachable VMs will be kept for further investigations.

        > **Note**: the resources related with the unreachable VMs become unmanaged by BOSH when `keep_unreachable_vms` or `keep_failed_vms` is `true`, so you need to clean up them manually once investigation is done. Typical unmanaged resources are listed as below. Go to Azure portal and delete the resources related to the failed VM accordinly.
        > * Virtual Machine.
        > * Network Interface.
        > * Dynamic public IP that attached to the VM.
        > * OS disk.
        > * Data disks that attached to the VM.

1. Enable VM boot diagnostics. The feature is enabled since CPI v26. With the feature, you will be able to get console output and screenshot of the VM. **Note**: AzureStack does not support VM boot diagnostics.

    - For CPI v26~v35.1.0.

        VM boot diagnostics is enabled when `debug_mode` is enabled in global CPI settings. Example:

        ```yaml
        properties:
          azure: &azure
            environment: AzureCloud
            subscription_id: ...
            ...
            debug_mode: true
        ```

    - For CPI v35.2.0+.

        Since v35.2.0, VM boot diagnostics will NOT be configured by `debug_mode` any more, a new configuration parameter `enable_vm_boot_diagnostics` is added to global CPI settings to turn on/off this feature. If you want to turn on the feature, you need to configure this parameter in global CPI settings. Example of enabling boot diagnostics:

        ```yaml
        properties:
          azure: &azure
            environment: AzureCloud
            subscription_id: ...
            ...
            enable_vm_boot_diagnostics: true
        ```

    > **Note**: VM boot diagnostics logs won't be cleaned up on VM delete, you can delete the logs manually if you want. When VM boot diagnostics is enabled, a storage account with tags `{'user-agent' => 'bosh', 'type' => 'bootdiagnostics'}` is created in the default resource group, and the boot diagnostics logs are stored in containers named as `bootdiagnostics-$vm_name[0:8]*` in that storage account.
    > You can use [cleanup-boot-diagnostics-logs.sh](./cleanup-boot-diagnostics-logs.sh) to clean up the diagnostics logs created by CPI v35.2.0+. Example:
    >   ```
    >     bash cleanup-boot-diagnostics-logs.sh my-cf-resource-group
    >   ```
