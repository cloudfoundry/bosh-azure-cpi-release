# BOSH Azure CPI Release

* Documentation: [bosh.io/docs](https://bosh.io/docs)
* Slack: #bosh-azure-cpi on <https://slack.cloudfoundry.org>
* Mailing list: [cf-bosh](https://lists.cloudfoundry.org/pipermail/cf-bosh)
* CI: <https://bosh-azure-cpi.ci.cf-app.com/>
* Roadmap: [Pivotal Tracker](https://www.pivotaltracker.com/n/projects/1133984) (label:azure)

This is a BOSH release for the Azure CPI.

See [Initializing a BOSH environment on Azure](https://bosh.io/docs/init-azure.html) for example usage.

## Development

See [development doc](docs/development.md).

## CHANGELOG
```
# 2015-03-14
- CPI changes
  - Assign public IP address to VMs directly

# 2016-03-11
- docs changes
  - Upgrade versions
    - Upgrade cf-release version to 231
    - Upgrade diego version to 0.1455.0
    - Upgrade etcd version to 36
    - Upgrade garden-linux version to 0.334.0
  - Refine docs to use the example manifests in ARM template.
  - Add changelog in README.md

# 2016-03-08
- CPI changes
  - Add ssh_public_key to replace ssh_certificate in manifest.

# 2016-02-24
- CPI changes
  - Add User-Agent in ARM HTTP request.

# 2016-02-15
- CPI changes
  - Add retry for Azure internal errors.
  - Add debug log for get_token.

# 2016-01-29
- docs changes
  - Add port 2222 for CF SSH proxy.

# 2016-01-28
- CPI changes
  - Prepare storage accounts if they do not exist.
```