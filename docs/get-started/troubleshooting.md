# Troubleshooting

1. api.cf.azurelovecf.com: no such host

  ```
  Error performing request: Get https://api.cf.azurelovecf.com/v2/info: dial tcp: lookup api.cf.azurelovecf.com: no such host
  ```

  If you hit the error when you try to login Cloud Foundry, you should check if your DNS is ready. You can prepare your own DNS and configure it properly. Otherwise, you can follow [**HERE**](./deploy-bosh-manually.md#setup-dns) to setup a DNS for testing quickly.

2. Director could not be targeted after VM restart, see [#55](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/55)

3. Failed to deploy BOSH with `get_token` error, see [#49](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/issues/49)

  You should verify whether the service principal is valid by [the steps](./create-service-principal.md#verify-your-service-principal).
