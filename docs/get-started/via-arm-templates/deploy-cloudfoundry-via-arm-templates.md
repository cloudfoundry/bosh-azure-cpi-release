# Deploy Cloud Foundry

>**NOTE:**
  * All the following commands must be run in your dev-box.
  * By default, this setction uses [xip.io](http://xip.io/) to resolve the system domain. More information, please click [**HERE**](../../advanced/deploy-azuredns).
  * Now by default, it uses the default storage account as the blobstore in multiple-vm-cf.yml.

Run `deploy_cloudfoundry.sh` in your home directory.

```
./deploy_cloudfoundry.sh <path-to-your-manifest>
```

For example:

```
./deploy_cloudfoundry.sh example_manifests/multiple-vm-cf.yml
```
