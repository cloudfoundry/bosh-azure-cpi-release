# BOSH Azure CPI Release

| Concourse Job      | Sub Job | Status                                                                                                                                                                                                                               |
| ---                | ---     | ---                                                                                                                                                                                                                             |
| BATS               | bats-ubuntu-managed-disks | [![bosh-azure-cpi.ci.cf-app.com](https://bosh-azure-cpi.ci.cf-app.com/api/v1/pipelines/azure-cpi/jobs/bats-ubuntu-managed-disks/badge)](https://bosh-azure-cpi.ci.cf-app.com/pipelines/azure-cpi/jobs/bats-ubuntu-managed-disks) |
|                    | bats-ubuntu-unmanaged-disks | [![bosh-azure-cpi.ci.cf-app.com](https://bosh-azure-cpi.ci.cf-app.com/api/v1/pipelines/azure-cpi/jobs/bats-ubuntu-unmanaged-disks/badge)](https://bosh-azure-cpi.ci.cf-app.com/pipelines/azure-cpi/jobs/bats-ubuntu-unmanaged-disks) |
| integration        | lifecycle-managed-disks | [![bosh-azure-cpi.ci.cf-app.com](https://bosh-azure-cpi.ci.cf-app.com/api/v1/pipelines/azure-cpi/jobs/lifecycle-managed-disks/badge)](https://bosh-azure-cpi.ci.cf-app.com/pipelines/azure-cpi/jobs/lifecycle-managed-disks) |
|                    | lifecycle-unmanaged-disks | [![bosh-azure-cpi.ci.cf-app.com](https://bosh-azure-cpi.ci.cf-app.com/api/v1/pipelines/azure-cpi/jobs/lifecycle-unmanaged-disks/badge)](https://bosh-azure-cpi.ci.cf-app.com/pipelines/azure-cpi/jobs/lifecycle-unmanaged-disks) |
| unit tests         | | [![bosh-azure-cpi.ci.cf-app.com](https://bosh-azure-cpi.ci.cf-app.com/api/v1/pipelines/azure-cpi/jobs/build-candidate/badge)](https://bosh-azure-cpi.ci.cf-app.com/pipelines/azure-cpi/jobs/build-candidate) |

* Documentation: [bosh.io/docs](https://bosh.io/docs)
* Slack: #bosh-azure-cpi on <https://slack.cloudfoundry.org>
* Mailing list: [cf-bosh](https://lists.cloudfoundry.org/pipermail/cf-bosh)
* CI: <https://bosh-azure-cpi.ci.cf-app.com/>
* Roadmap: [Pivotal Tracker](https://www.pivotaltracker.com/n/projects/1133984) (label:azure)

This is a BOSH release for the Azure CPI.

See [Initializing a BOSH environment on Azure](https://bosh.io/docs/init-azure.html) for example usage.

## Development

See [development doc](docs/development.md).
