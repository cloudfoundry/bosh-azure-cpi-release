# BOSH Azure CPI Concourse Pipeline

In order to run the BOSH Azure CPI Concourse Pipeline you must have an existing [Concourse](http://concourse.ci) environment. See [Deploying Concourse on Azure](https://github.com/Azure/azure-quickstart-templates/tree/master/concourse-ci) for instructions, if you don't have one.

* Target your Concourse CI environment:

```
fly -t azure login -c <YOUR CONCOURSE URL>
```

* Update the [credentials.yml](./credentials.yml) file.
 
* Set the BOSH Azure CPI pipeline:

```
fly -t azure set-pipeline -p bosh-azure-cpi -c pipeline.yml -l credentials.yml
```

* Unpause the BOSH Azure CPI pipeline:

```
fly -t azure unpause-pipeline -p bosh-azure-cpi
```
