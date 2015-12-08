# Deploy Cloud Foundry

>**NOTE:** All the following commands must be run in your dev-box.

1. Upload stemcell

  Get the value of **resource_pools.name[vms].stemcell.url** in [**bosh.yml**](https://github.com/Azure/azure-quickstart-templates/blob/master/bosh-setup/bosh.yml), then use it to replace **STEMCELL-FOR-AZURE-URL** in below command:

  ```
  bosh upload stemcell STEMCELL-FOR-AZURE-URL
  ```

2. Upload Cloud Foundry release v224

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  ```

  >**NOTE:** If you want to use the latest Cloud Foundry version, the Azure part in the manifest is same but other configurations may be different. You need to change them manually.

3. Deploy

  ```
  bosh deployment YOUR-MANIFEST-FOR-CLOUD-FOUNDRY # cf_224.yml
  bosh deploy
  ```

>**NOTE:**
  * If you hit any issue, please see [**troubleshooting**](./troubleshooting.md), [**known issues**](./known-issues.md) and [**migration**](./migration.md). If it does not work, you can file an issue [**HERE**](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues).
