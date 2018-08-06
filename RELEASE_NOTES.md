Features:

- CPI Supports enabling accelerated networking for VM network interface. (#410)

  By default, accelerated networking is disabled. To enable it, you can set `accelerated_networking` in `vm_types` or `vm_extensions` or network configuration to `true`. The `accelerated_networking` in `vm_types/vm_extensions` can override the equivalent option in the network configuration. See the [doc](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/advanced/accelerated-networking/README.md) for details.

- CPI supports custom tags for VMs. (#425)

  A new cloud property `tags` is added in `vm_types` or `vm_extensions`. They are name-value pairs.

  * Before configuring it, please review [the limitations apply to tags](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-using-tags).

  * In Azure, each VM can have a maximum of 15 tag name-value pairs. Currently, BOSH director and Azure CPI use at most 10 tags. So it's not recommended to use more than 3 custom tags.

Fixes:

- Remove extra md5 calculation when uploading blobs. (#413)

- Split the low level retry (network errors) and the high level retry (http status code). (#421)

- Bump to ruby 2.4.4. (#409)

Documents:

- Deploy Cloud Foundry with Traffic Manager. (#406)

- Use goblob + minio to migrate blobs from an NFS blobstore to an Azure Storage blobstore. (#418)

Development:

- Enable the rubocop. (#407)

- Enable Jenkins CI for rubocop check and unit tests. (#414)

- Add a script to test the creating/deleting performance. (#416)
