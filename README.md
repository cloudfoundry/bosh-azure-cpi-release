# BOSH Azure Cloud Provider Interface

## Options

These options are passed to the Azure CPI when it is instantiated.

### Azure options

* `environment` (required)
  The environment for Azure Management Service: AzureCloud or AzureChinaCloud
* `subscription_id` (required)
  Azure Subscription Id
* `storage_account_name` (required)
  Azure storage account name
* `storage_access_key` (required)
  Azure storage access key
* `resource_group_name` (required)
  Resource group name to use when spinning up new vms
* `tenant_id` (required)
  The tenant id for your service principal
* `client_id` (required)
  The client id for your service principal
* `client_secret` (required)
  The client secret for your service principal
* `ssh_user` (required)
  The user to use when spinning up new vms
* `ssh_certificate` (required)
  The content of the default certificate to use when spinning up new vms

### Registry options

The registry options are passed to the Azure CPI by the BOSH director based on the settings in `director.yml`, but can be
overridden if needed.

* `endpoint` (required)
  registry URL
* `user` (required)
  registry user
* `password` (required)
  registry password

### Agent options

Agent options are passed to the Azure CPI by the BOSH director based on the settings in `director.yml`, but can be
overridden if needed.

### Resource pool options

These options are specified under `cloud_options` in the `resource_pools` section of a BOSH deployment manifest.

* `instance_type` (required)
  which [type of instance](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-size-specs/) the VMs should belong to

### Network options

These options are specified under `cloud_options` in the `networks` section of a BOSH deployment manifest.

* `type` (required)
  can be either `dynamic` for a DHCP assigned IP by Azure, or 'manual' to use an assigned IP by BOSH director,
  or `vip` to use a reserved public IP (which needs to be already allocated)

## Examples
Below is a sample of how Azure specific properties are used in a BOSH deployment manifest:

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
      cloud_properties:
        tcp_endpoints:
        - "22:22"
        - "53:53"
        - "4222:4222"
        - "6868:6868"
        - "25250:25250"
        - "25555:25555"
        - "25777:25777"
        udp_endpoints:
        - "68:68"
    - name: private
      type: manual
      subnets:
      - range: 10.0.0.0/24
        gateway: 10.0.0.1
        dns: [8.8.8.8]
        cloud_properties:
          virtual_network_name: boshnet
          subnet_name: subnet1

    resource_pools:
    - name: vms
      network: private
      stemcell:
        # bosh-azure-hyperv-ubuntu-trusty-go_agent
        url: file://~/Downloads/stemcell.tgz
      cloud_properties:
        instance_type: Standard_D1

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
      - {name: private, static_ips: [10.0.0.4]}
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
          address: 10.0.0.4
          host: 10.0.0.4
          db: *db
          http: {user: admin, password: admin, port: 25777}
          username: admin
          password: admin
          port: 25777

        # Tells the Director/agents how to contact blobstore
        blobstore:
          address: 10.0.0.4
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
          environment: AzureCloud
          subscription_id: <your_subscription_id>
          storage_account_name: <your_storage_account_name>
          storage_access_key: <your_storage_access_key>
          resource_group_name: <your_resource_group_name>
          tenant_id: <your_tenant_id>
          client_id: <your_client_id>
          client_secret: <your_client_secret>
          ssh_user: vcap
          ssh_certificate: "-----BEGIN CERTIFICATE-----\n..."

        # Tells agents how to contact nats
        agent: {mbus: "nats://nats:nats-password@10.0.0.4:4222"}

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