# Configure Azure Load Balancer Backend Pools

Azure Load Balancer supports two backend pool membership types. The Azure CPI can use either type when creating a VM:

* `nic` associates the VM's network interface IP configuration with the backend pool. This is the default and preserves the existing CPI behavior.
* `ip` adds the VM's private IP address and virtual network ID directly to the backend pool.

The backend pool must already exist on the load balancer. The CPI does not create the load balancer or migrate its backend pools.

## Configure a NIC-based backend pool

Omit `default_backend_pool_type` or set it to `nic`:

```yaml
vm_types:
- name: router
  cloud_properties:
    instance_type: Standard_D2s_v3
    load_balancer:
    - name: cf-load-balancer
      backend_pool_name: router-pool
      default_backend_pool_type: nic
```

For NIC-based pools, Azure associates the NIC IP configuration with the selected backend pool while the NIC is created.

## Configure an IP-based backend pool

Set `default_backend_pool_type` to `ip` on the load balancer configuration:

```yaml
vm_types:
- name: router
  cloud_properties:
    instance_type: Standard_D2s_v3
    load_balancer:
    - name: cf-load-balancer
      backend_pool_name: router-pool
      default_backend_pool_type: ip
```

After creating the VM, the CPI adds its private IPv4 address and virtual network ID to `router-pool`. For a dual-stack VM, use `backend_pool_name_v6` to select the IPv6 pool:

```yaml
load_balancer:
- name: cf-load-balancer
  backend_pool_name: router-pool-v4
  backend_pool_name_v6: router-pool-v6
  default_backend_pool_type: ip
```

Valid values for `default_backend_pool_type` are `nic` and `ip`. When the property is omitted, it defaults to `nic`.

## Assign a VM to multiple backend pools

IP-based membership allows a VM to be assigned to multiple load balancers or multiple backend pools. Add one array entry for each backend pool. To target multiple pools on the same load balancer, repeat the load balancer name:

```yaml
load_balancer:
- name: public-load-balancer
  backend_pool_name: web-pool
  default_backend_pool_type: ip
- name: internal-load-balancer
  backend_pool_name: services-pool
  default_backend_pool_type: ip
- name: internal-load-balancer
  backend_pool_name: management-pool
  default_backend_pool_type: ip
```

The CPI adds each newly created VM to every configured IP-based backend pool.

## Migrate an existing pool from NIC-based to IP-based

Changing `default_backend_pool_type` does not migrate an existing Azure backend pool. Migrate the pool in Azure first, verify the result, and then update the BOSH cloud configuration.

1. Record the load balancer name and every backend pool that you want to migrate.
2. Back up the current load balancer configuration and plan for the operational impact of changing backend membership.
3. Call the Azure `migrateToIpBased` operation with API version `2025-07-01`. The request body contains the pool names:

```http
POST https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/loadBalancers/<load-balancer-name>/migrateToIpBased?api-version=2025-07-01
Content-Type: application/json

{
    "pools": [
    "router-pool"
    ]
}
```

4. Confirm that Azure reports the expected pools in `migratedPools` and verify that existing backend addresses and load-balancing rules still operate as expected.
5. Set `default_backend_pool_type: ip` for each migrated pool in the BOSH cloud configuration.
6. Run `bosh update-cloud-config` and recreate or redeploy the affected instances. Newly created VMs are registered in the pools by private IP.

For the complete request contract and current Azure requirements, see [Migrate Load Balancer backend pools to IP-based membership](https://learn.microsoft.com/en-us/rest/api/load-balancer/load-balancers/migrate-to-ip-based?view=rest-load-balancer-2025-07-01&tabs=HTTP).

Do not set `default_backend_pool_type: ip` before the Azure pool is IP-based. Also do not use the setting to describe a NIC-based pool as IP-based; it controls how the CPI registers new VMs and is not a migration command.

