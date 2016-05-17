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
# 2015-05-17
- CPI changes
  - Fix an issue in calculating the sleep interval when copying blobs
  - Use LUN and host device id as the disk identifier
    - Compatible Stemcell Versions: v3181 or later

# 2015-05-09
- CPI changes
  - Remove use_temporary_disk and always use a data disk as the ephemeral disk.

# 2015-04-25
- CPI changes
  - Support to use a data disk as the ephemeral disk.

# 2015-04-20
- CPI changes
  - Upgrade azure-sdk-for-ruby version to 0.7.4.
  - Add AzureChinaCloud support.
  - Add AzureStack support.

# 2015-04-15
- CPI changes
  - Auto retry when an internal error occurs in asynchronous operation.
  - Do not include development gems when building CPI release. 

# 2015-04-13
- CPI changes
  - Reduce retry interval to improve performance.

# 2015-04-12
- CPI changes
  - Raise an error if instance_type is not provided.

# 2015-04-06
- docs changes
  - Update Diego manifest to fix the issue that HAPROXY always reloads every 10 seconds.
  - Correct manifest path in the dev-box which is created by ARM template.
- CI changes
  - Set password for director account in environment variables for BATs to enhance security.

# 2015-03-30
- CPI changes
  - Allow to bind network security group to VMs.

# 2015-03-25
- docs changes
  - Add network security group
  - Change default DNS from 8.8.8.8 to 168.63.129.16 (Azure default virtual DNS server)
  - Change parameter format in command lines from <PARAM> to $PARAM
- CPI changes
  - Add retry when failing to resolve a DNS name.

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