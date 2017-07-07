# Configuration for Resource Groups

By default, Azure CPI creates all resources in the `default resource group` which is specified as `resource_group_name` in [Global Configuration](https://bosh.io/docs/aws-cpi.html#global).
However, it is configurable to seperate some resources to different resource groups for different purposes.

See available configrations -
1. [separate network in a different resource group](./separate-network-in-a-different-resource-group.md)
1. [separate vm in a different resource group](./separate-vm-in-a-different-resource-group.md)
