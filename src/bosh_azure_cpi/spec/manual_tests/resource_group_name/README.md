# Manual test

## Purpose

To verify the feature of `multiple resource group` for VMs, make sure it is compatible with old versions.

## Environment setup

1. setup bosh registry following [this guidance](../../../../../docs/development.md).

1. prepare bosh environment. If you have deployed a bosh director by this [guidance](../../../../../docs/get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) and uploaded a stemcell, you have everything prepared.

1. fill related information in ./cpi.cfg to use resource created by previous step.

1. change `stemcell_id` in ./test.cfg to use the stemcell you have uploaded in previous step.

## Run test

```bash
  ruby ./migrate_to_new_rg.rb
```

