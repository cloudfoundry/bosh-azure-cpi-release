# BOSH Azure CPI Concourse Pipeline

In order to run the BOSH Azure CPI Concourse Pipeline you must have an existing [Concourse](http://concourse.ci) environment. See [Deploying Concourse on Azure](https://github.com/Azure/azure-quickstart-templates/tree/master/concourse-ci) for instructions, if you don't have one.

1. Target your Concourse CI environment:

    ```
    fly -t azure login -c <YOUR CONCOURSE URL>
    ```

1. Setup a develop pipeline

    1. Create a storage account on Azure.

        1. Copy the storage account name and access key.

        1. Create two containers in the storage account, and copy the container name.

            * The first container is to store Azure CPI dev artifacts

            * The second container is to store environment terraform state

    1. Create a Github repository.

        1. Copy the repository URL and [deploy keys](https://developer.github.com/v3/guides/managing-deploy-keys/#deploy-keys).

        1. Create a file `current-version` with the content `0.0.0`.

    1. Update the [credentials-develop.yml](./develop/credentials-develop.yml) file.
 
    1. Set the BOSH Azure CPI pipeline:

        ```
        fly -t azure set-pipeline -p bosh-azure-cpi-develop -c develop/pipeline-develop.yml -l develop/credentials-develop.yml
        ```

    1. Unpause the BOSH Azure CPI pipeline:

        ```
        fly -t azure unpause-pipeline -p bosh-azure-cpi-develop
        ```

1. Setup an official pipeline. If you are not the owner of the repository, you can skip this step.

    1. Update the [credentials.yml](./credentials.yml) file.
 
    1. Set the BOSH Azure CPI pipeline:

        ```
        fly -t azure set-pipeline -p bosh-azure-cpi -c pipeline.yml -l credentials.yml
        ```

    1. Unpause the BOSH Azure CPI pipeline:

        ```
        fly -t azure unpause-pipeline -p bosh-azure-cpi
        ```
