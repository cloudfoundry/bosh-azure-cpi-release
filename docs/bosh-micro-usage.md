## Experimental `bosh-micro` usage

!!! `bosh-micro` CLI is still being worked on !!!

To start experimenting with bosh-azure-cpi release and new bosh-micro cli:

1. Create a deployment directory

```
mkdir my-micro
```

1. Create `manifest.yml` inside deployment directory with following contents

```
---
name: bosh

networks:
- name: public
  type: vip
  cloud_properties: {}
- name: private
  type: manual
  ip:   10.0.0.7
  dns:  [10.0.0.4]
  cloud_properties:
    virtual_network_name: boshvnet
    subnet_name: BOSH
    tcp_endpoints:
    - 4222:4222
    - 25777:25777
    - 25250:25250
    - 6868:6868
    - 25555:25555

resource_pools:
- name: default
  network: private
  stemcell:
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  cloud_properties:
    instance_type: Small

disk_pools:
- name: my-persistent-disk
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
  persistent_disk_pool: my-persistent-disk

  networks:
  - name: private
  - name: public
    static_ips: [__PUBLIC_IP__]

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
      cpi_job: cpi # Use external AWS CPI

    hm:
      http: {user: hm, password: hm-password}
      director_account: {user: admin, password: admin}

    azure: &azure
      management_endpoint: https://management.core.windows.net
      subscription_id: <your_subscription_id>
      management_certificate: "<base64_encoding_content_of_your_management_certificate>"
      storage_account_name: <your_storage_account_name>
      storage_access_key: <your_storage_access_key>
      ssh_certificate: "<base64_encoding_content_of_your_ssh_certificate>"
      ssh_private_key: "<base64_encoding_content_of_your_ssh_private_key>"
      affinity_group_name: <youre_affinity_group_name>

    # Tells agents how to contact nats
    agent: {mbus: "nats://nats:nats-password@10.0.0.7:4222"}

    ntp: &ntp [0.north-america.pool.ntp.org]

cloud_provider:
  template: {name: cpi, release: bosh-azure-cpi}

  # Tells bosh-micro how to SSH into deployed VM
  ssh_tunnel:
    host: __PUBLIC_IP__
    port: 22
    user: vcap
    private_key: /Users/pivotal/Downloads/new-bosh.pem

  # Tells bosh-micro where to run registry on a user's machine while deploying
  registry: &registry
    host: 127.0.0.1
    port: 6901
    username: registry-user
    password: registry-password

  # Tells bosh-micro how to contact remote agent
  mbus: https://mbus-user:mbus-password@__PUBLIC_IP__:6868

  properties:
    azure: *azure

    # Tells CPI how agent should listen for bosh-micro requests
    agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

    # Tells CPI how to contact registry
    registry: *registry

    blobstore:
      provider: local
      path: /var/vcap/micro_bosh/data/cache

    ntp: *ntp
```

1. Set deployment

```
bosh-micro deployment my-micro/manifest.yml
```

1. Kick off a deploy with stemcell, BOSH release, and CPI release

```
bosh-micro deploy ~/Downloads/???-xen-ubuntu-trusty-go_agent.tgz ~/Downloads/bosh-?.tgz ~/Downloads/bosh-azure-cpi-?.tgz
```
