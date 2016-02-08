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
      bosh delete deployment <CLOUD-FOUNDRY-DEPLOYMENT-NAME>
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

2. "NicInUse" error when deleting the network interfaces

  ```
  D, [2015-08-27 05:36:41#44885] [] DEBUG -- DirectorJobRunner: Worker thread raised exception: Unknown CPI error 'Bosh::AzureCloud::AzureError' with message 'http_delete - error: 400 message: 
  {
      "error": {
          "code": "NicInUse",
          "message": "Network Interface /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/abel-beta/providers/Microsoft.Network/networkInterfaces/dc0d3a9a-0b00-40d8-830d-41e6f4ac9809 is used by existing VM /subscriptions/87654321-1234-5678-1234-678912345678/resourceGroups/abel-beta/providers/Microsoft.Compute/virtualMachines/dc0d3a9a-0b00-40d8-830d-41e6f4ac9809.",
          "details": []
      }
  }
  ```

  If you hits the similar issue, you can retry the same command manually. If it does not work, you can file a support ticket. Please refer to https://azure.microsoft.com/en-us/support/options/ and https://azure.microsoft.com/en-us/support/faq/.
