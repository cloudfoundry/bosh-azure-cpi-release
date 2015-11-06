# Migration from Preview 2

If you are customers of [Cloud Foundry on Azure Preview 2](https://azure.microsoft.com/en-us/blog/cloud-foundry-on-azure-preview-2-now-available/), you may hit the following errors when you deploy Cloud Foundry on Azure using the latest CPI and guidance.

1. Error installing bosh_cli

  * Error

    ```
    ERROR:  Error installing bosh_cli:
            net-ssh requires Ruby version >= 2.0.
    ```

  * Solution: You need to upgrade Ruby version.

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

2. Failed to render job templates for instance 'bosh/0'

  * Error

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

  * Solution: You need to upgrade Ruby version.

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
    ```

    Click https://github.com/cloudfoundry/bosh-init/pull/46 to learn more.

3. "ContainerNotFound" error

  * Error

    ```
    CPI 'create_stemcell' method responded with error: CmdError{"type":"Bosh::Clouds::CloudError","message":"Failed to upload page blob: Failed to upload page blob: ContainerNotFound (404): The specified container does not exist.
    ```

  * Solution: You need to create containers `bosh` and `stemcell` in your default storage account.

    ```
    azure storage account keys list -g <resource-group-name> <storage-account-name>
    azure storage container create -a <storage-account-name> -k <storage-account-key> bosh
    azure storage container create -a <storage-account-name> -k <storage-account-key> -p Blob stemcell
    ```

    The permission of the container `stemcell` in your default storage account is set as `Public read access for blobs only` (`Blob`) to support multiple storage accounts.

    Click [**HERE**](./deploy-bosh-manually.md#133-create-containers) to learn more.

4. "TableNotFound" error

  * Error

    ```
    I, [2015-11-04T22:32:17.565003 #59521]  INFO -- : has_stemcell?(yourstoragename, bosh-stemcell-12874321-1234-5678-1234-678912345678)
    I, [2015-11-04T22:32:17.570148 #59521]  INFO -- : has_table?(stemcells)

    ...

    D, [2015-11-04 22:32:17 #59219] [] DEBUG -- DirectorJobRunner: Worker thread raised exception: Unknown CPI error 'Unknown' with message 'TableNotFound (404): The table specified does not exist.
    ```

  * Solution: To support multiple storage accounts, you need to create a table `stemcells` in your default storage account.

    ```
    azure storage account keys list -g <resource-group-name> <storage-account-name>
    azure storage table create -a <storage-account-name> -k <storage-account-key> stemcells
    ```

    Click [**HERE**](./deploy-bosh-manually.md#134-create-tables) to learn more.
