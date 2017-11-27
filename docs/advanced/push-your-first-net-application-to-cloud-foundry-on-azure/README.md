# Push Your First NET Application to Cloud Foundry on Azure

This guidance is based on the [bosh-setup template v3.0.0+](https://github.com/Azure/azure-quickstart-templates/tree/master/bosh-setup) and [the windows cell ops file in cf-deployment](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/windows-cell.yml).

If you want to run ASP.NET applications based on the older bosh-setup template than v3.0.0, you can refer to two other ways:

* With [`windows2012R2` stack](./run-asp-net-apps-with-windows2012R2-stack.md)
  * Requires Diego-Windows, Garden-Windows
  * Supports .NET SDK 3.5-4.5+
  * Uses `binary_buildpack` (applications are pre-compiled, no detect) to deploy the applications

* With [`cflinuxfs2` stack](./run-asp-net-apps-with-cflinuxfs2-stack.md)
  * Standard CF Linux Stack
  * Supports ASP.NET Core only
  * Uses community ASP.NET buildpack to deploy the applications

## Deploy windows cells

1. Download the windows stemcell ops file [windows-cell.yml](https://github.com/cloudfoundry/cf-deployment/blob/master/operations/windows-cell.yml).

    ```
    wget https://raw.githubusercontent.com/cloudfoundry/cf-deployment/master/operations/windows-cell.yml -O ~/windows-cell.yml
    ```

    By default, the [bosh-setup template v3.0.0+](https://github.com/Azure/azure-quickstart-templates/tree/master/bosh-setup) uses Azure Storage as blobstore. So the local blobstore tls should be removed. You can remove the following contents in windows-cell.yml.

    ```
    executor:
      ca_certs_for_downloads: ((blobstore_tls.ca))
    ```

1. Download the [windows stemcell](https://bosh.io/stemcells/bosh-azure-hyperv-windows2012R2-go_agent) based on the stemcell version in windows-cell.yml.

    For example,

    ```
    bosh upload-stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-windows2012R2-go_agent
    ```

1. Deploy!

    Add the line `-o ~/windows-cell.yml` to the `bosh -n -d cf deploy` command in `deploy_cloud_foundry.sh`, and deploy Cloud Foundry.

    ```
    ./deploy_cloud_foundry.sh
    ```

## Push your first .NET application

1. Clone the [.NET sample application](https://github.com/cloudfoundry-incubator/NET-sample-app).

    ```
    git clone https://github.com/cloudfoundry-incubator/NET-sample-app
    ```

1. Login Cloud Foundry.

    ```
    ./login_cloud_foundry.sh
    ```

1. Create the space if needed, and target the space.

    ```
    cf create-space azure
    cf target -o "system" -s "azure"
    ```

1. Push the application.

    ```
    cd NET-sample-app
    cf push environment -s windows2012R2 -b hwc_buildpack -p ./ViewEnvironment/
    ```
