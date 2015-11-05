# Known Issues

1. If your deployment fails because of timeout when creating VMs, you can delete your deployment and try to deploy it again.

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

3. api.cf.azurelovecf.com: no such host

  ```
  Error performing request: Get https://api.cf.azurelovecf.com/v2/info: dial tcp: lookup api.cf.azurelovecf.com: no such host
  ```

  If you hit the error when you try to login Cloud Foundry, you should check if your DNS is ready. You can prepare your own DNS and configure it properly. Otherwise, you can follow [**HERE**](./deploy-bosh-manually.md#3-setup-dns) to setup a DNS for testing quickly.
