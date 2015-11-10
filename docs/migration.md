# Migration from Preview 2

If you are customers of [Cloud Foundry on Azure Preview 2](https://azure.microsoft.com/en-us/blog/cloud-foundry-on-azure-preview-2-now-available/), you need to do the following migration.

## Migration

1. Update bosh.yml.

  Replace **BOSH-FOR-AZURE-URL**, **BOSH-FOR-AZURE-SHA1**, **BOSH-AZURE-CPI-URL**, **BOSH-AZURE-CPI-SHA1**, **STEMCELL-FOR-AZURE-URL** and **STEMCELL-FOR-AZURE-SHA1** with the values in the example file [**bosh.yml**](https://github.com/Azure/azure-quickstart-templates/blob/master/bosh-setup/bosh.yml).

  Click [**HERE**](./deploy-bosh-manually.md#configure_bosh_yml) to learn more.

2. You need to upgrade Ruby version in your dev-box.

  ```
  sudo apt-get install -y ruby2.0 ruby2.0-dev

  sudo rm /usr/bin/ruby /usr/bin/gem /usr/bin/irb /usr/bin/rdoc /usr/bin/erb
  sudo ln -s /usr/bin/ruby2.0 /usr/bin/ruby
  sudo ln -s /usr/bin/gem2.0 /usr/bin/gem
  sudo ln -s /usr/bin/irb2.0 /usr/bin/irb
  sudo ln -s /usr/bin/rdoc2.0 /usr/bin/rdoc
  sudo ln -s /usr/bin/erb2.0 /usr/bin/erb
  sudo gem update --system
  sudo gem pristine --all

  sudo gem install bosh_cli -v 1.3016.0 --no-ri --no-rdoc
  ```

  If this step is not done, you may hit the error [**#1**](#error_installing_bosh_cli) and [**#2**](#failed_to_render_job_templates).

3. You need to do the following migrations if your want to enable multiple storage accounts.
  1. You need to set the permission of the container `stemcell` as `Blob` in your default storage account.

    ```
    azure storage account keys list -g <resource-group-name> <storage-account-name>
    azure storage container set -a <storage-account-name> -k <storage-account-key> -p Blob stemcell
    ```

    To support multiple storage accounts, the permission of the container `stemcell` in your default storage account should be set as `Blob` which means `Public read access for blobs only`.

    If this step is not done, you may hit the error [**#3**](#cannot_verify_copy_source).

  2. To support multiple storage accounts, you need to create a table `stemcells` in your default storage account.

    ```
    azure storage account keys list -g <resource-group-name> <storage-account-name>
    azure storage table create -a <storage-account-name> -k <storage-account-key> stemcells
    ```

    If this step is not done, you may hit the error [**#4**](#table_not_found).

  3. Create another storage account and containers in it manually.

    ```
    azure storage account create -l <location> --type <account-type> -g <resource-group-name> <another-storage-account-name>
    azure storage container create -a <storage-account-name> -k <storage-account-key> bosh
    azure storage container create -a <storage-account-name> -k <storage-account-key> stemcell
    ```

    If this step is not done, you may hit the error [**#5**](#storage_account_not_found).

  Please click [**HERE**](../src/bosh_azure_cpi/README.md) to learn more new settings.

## Error

<a name="error_installing_bosh_cli"></a>
1. Error installing bosh_cli

  You may get an error in `~/install.log`.

  ```
  ERROR:  Error installing bosh_cli:
          net-ssh requires Ruby version >= 2.0.
  ```


<a name="failed_to_render_job_templates"></a>
2. Failed to render job templates for instance 'bosh/0'

  ```
  Command 'deploy' failed:
    Deploying:
      Building state for instance 'bosh/0':
        Rendering job templates for instance 'bosh/0':
          Rendering templates for job 'director/YWJhZDYyNTA2YjZmOGI0MTlmZGM4ZjQyYTllOTk2NzA0NTA1N2I0NQ==':
            Rendering template src: director.yml.erb.erb, dst: config/director.yml.erb:
              Rendering template src: /tmp/bosh-init-release841286293/extracted_jobs/director/templates/director.yml.erb.erb, dst: /tmp/rendered-jobs017016761/config/director.yml.erb:
                Running ruby to render templates:
                  Running command: 'ruby /tmp/erb-renderer786454619/erb-render.rb /tmp/erb-renderer786454619/erb-context.json /tmp/bosh-init-release841286293/extracted_jobs/director/templates/director.yml.erb.erb /tmp/rendered-jobs017016761/config/director.yml.erb', stdout: '', stderr: '/tmp/erb-renderer786454619/erb-render.rb:180:in `rescue in render': Error filling in template '/tmp/bosh-init-release841286293/extracted_jobs/director/templates/director.yml.erb.erb' for director/0 (line 136: #<JSON::GeneratorError: only generation of JSON objects or arrays allowed>) (RuntimeError)
          from /tmp/erb-renderer786454619/erb-render.rb:166:in `render'
          from /tmp/erb-renderer786454619/erb-render.rb:191:in `<main>'
  ':
                    exit status 1
  ```

<a name="cannot_verify_copy_source"></a>
3. "CannotVerifyCopySource" error

  ```
  Error 100: Unknown CPI error 'Unknown' with message 'CannotVerifyCopySource (404): The specified resource does not exist.
  ```

<a name="table_not_found"></a>
4. "TableNotFound" error

  ```
  Error 100: Unknown CPI error 'Unknown' with message 'TableNotFound (404): The table specified does not exist.
  ```

<a name="storage_account_not_found"></a>
5. Storage account not found

  ```
  Error 100: Unknown CPI error 'Bosh::AzureCloud::AzureError' with message 'http_post - error: 404 message: {"error":{"code":"ResourceNotFound","message":"The Resource 'Microsoft.Storage/storageAccounts/<your-storage-account>' under resource group '<your-resource-group>' was not found."}}'
  ```
