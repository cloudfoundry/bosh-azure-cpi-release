## Experimental `bosh-init` usage

!!! `bosh-init` CLI is still being worked on !!!

To start experimenting with bosh-azure-cpi release and new bosh-init cli:

1. Create a deployment directory

```
mkdir my-bosh
```

1. Create `bosh.yml` inside deployment directory with following contents

```yaml
---
name: bosh

releases:
- name: bosh
  url: https://bosh.io/d/github.com/cloudfoundry/bosh?v=158
  sha1: a97811864b96bee096477961b5b4dadd449224b4
- name: bosh-azure-cpi
  url: file://../dev_releases/bosh-azure-cpi/bosh-azure-cpi-0+dev.21.tgz

networks:
- name: public
  type: vip
- name: private
  type: manual
  subnets:
  - range: 10.0.0.0/24
    gateway: 10.0.0.1
    dns: [8.8.8.8]
    cloud_properties:
      virtual_network_name: boshnet
      subnet_name: subnet1
      tcp_endpoints:
      - 4222:4222
      - 25777:25777
      - 25250:25250
      - 6868:6868
      - 25555:25555

resource_pools:
- name: vms
  network: private
  stemcell:
    # bosh-azure-hyperv-ubuntu-trusty-go_agent
    url: file://~/Downloads/stemcell.tgz
  cloud_properties:
    instance_type: Small

disk_pools:
- name: disks
  disk_size: 25_000

jobs:
- name: bosh
  templates:
  - {name: nats, release: bosh}
  - {name: redis, release: bosh}
  - {name: postgres, release: bosh}
  - {name: blobstore, release: bosh}
  - {name: director, release: bosh}
  - {name: health_monitor, release: bosh}
  - {name: registry, release: bosh}
  - {name: cpi, release: bosh-azure-cpi}

  instances: 1
  resource_pool: vms
  persistent_disk_pool: disks

  networks:
  - {name: private, static_ips: [10.0.0.7]}
  - {name: public, static_ips: [__PUBLIC_IP__]}

  properties:
    nats:
      address: 127.0.0.1
      user: nats
      password: nats-password

    redis:
      listen_addresss: 127.0.0.1
      address: 127.0.0.1
      password: redis-password

    postgres: &db
      host: 127.0.0.1
      user: postgres
      password: postgres-password
      database: bosh
      adapter: postgres

    # Tells the Director/agents how to contact registry
    registry:
      address: 10.0.0.7
      host: 10.0.0.7
      db: *db
      http: {user: admin, password: admin, port: 25777}
      username: admin
      password: admin
      port: 25777

    # Tells the Director/agents how to contact blobstore
    blobstore:
      address: 10.0.0.7
      port: 25250
      provider: dav
      director: {user: director, password: director-password}
      agent: {user: agent, password: agent-password}

    director:
      address: 127.0.0.1
      name: bosh
      db: *db
      cpi_job: cpi

    hm:
      http: {user: hm, password: hm-password}
      director_account: {user: admin, password: admin}

    azure: &azure
      subscription_id: 9eec...
      affinity_group_name: bosh
      management_endpoint: https://management.core.windows.net
      management_certificate: "-----BEGIN RSA PRIVATE KEY-----\n..."
      storage_account_name: bosh...
      storage_access_key: "n6Qi..."
      ssh_user: vcap
      ssh_certificate: "-----BEGIN CERTIFICATE-----\n..."
      ssh_private_key: "-----BEGIN RSA PRIVATE KEY-----\n..."

    # Tells agents how to contact nats
    agent: {mbus: "nats://nats:nats-password@10.0.0.7:4222"}

    ntp: &ntp [0.north-america.pool.ntp.org]

cloud_provider:
  template: {name: cpi, release: bosh-azure-cpi}

  # Tells bosh-init how to SSH into deployed VM
  ssh_tunnel:
    host: __PUBLIC_IP__
    port: 22
    user: vcap
    private_key: ~/.ssh/bosh

  # Tells bosh-init how to contact remote agent
  mbus: https://mbus-user:mbus-password@__PUBLIC_IP__:6868

  properties:
    azure: *azure

    # Tells CPI how agent should listen for bosh-init requests
    agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}

    ntp: *ntp
```

1. Kick off a deploy with stemcell, BOSH release, and CPI release

```
cd my-bosh && bosh-init deploy bosh.yml
```
