#!/usr/bin/env bash

set -e
echo "deploy.sh..."
source bosh-cpi-release/ci/tasks/utils.sh
source azure-exports/azure-exports.sh

check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_TENANT_ID
check_param AZURE_GROUP_NAME
check_param AZURE_VNET_NAME
check_param AZURE_STORAGE_ACCOUNT_NAME
check_param AZURE_SUBSCRIPTION_ID
check_param AZURE_BOSH_SUBNET_NAME
check_param base_os
check_param private_key_data
check_param ssh_certificate
check_param DIRECTOR
check_param AZURE_STORAGE_ACCESS_KEY
check_param BAT_NETWORK_GATEWAY
check_param STEMCELL_URL
check_param STEMCELL_SHA

echo "Checking params from previous steps..."
echo "show directory ip..."
echo "$DIRECTOR"

source /etc/profile.d/chruby.sh
chruby 2.1.2

semver=`cat version-semver/number`
cpi_release_name=bosh-azure-cpi
working_dir=$PWD
manifest_dir="${working_dir}/director-state-file"
manifest_filename=${manifest_dir}/${base_os}-director-manifest.yml

mkdir -p $manifest_dir/keys
echo "$private_key_data" > $manifest_dir/keys/bats.pem

eval $(ssh-agent)
chmod go-r $manifest_dir/keys/bats.pem
ssh-add $manifest_dir/keys/bats.pem

#create director manifest as heredoc
cat > "${manifest_filename}"<<EOF
---
name: bosh

releases:
- name: bosh
  url: http://cloudfoundry.blob.core.windows.net/azureci/bosh-214+dev.1.tgz
  sha1: c28477c7e08cce06add980bed0ab1ab113a7c825
- name: bosh-azure-cpi
  url: file://tmp/bosh-azure-cpi.tgz

networks:
- name: public
  type: vip
  cloud_properties:
    tcp_endpoints:
    - "22:22"
    - "4222:4222"
    - "6868:6868"
    - "25250:25250"
    - "25555:25555"
    - "25777:25777"
    udp_endpoints:
    - "68:68"
    - "53:53"
- name: private
  type: manual
  subnets:
  - range: 10.0.0.0/24
    gateway: 10.0.0.1
    dns: [8.8.8.8]
    cloud_properties:
      virtual_network_name: $AZURE_VNET_NAME
      subnet_name: $AZURE_BOSH_SUBNET_NAME

resource_pools:
- name: vms
  network: private
  stemcell:
    url: $STEMCELL_URL
    sha1: $STEMCELL_SHA
  cloud_properties:
    instance_type: Standard_D1

disk_pools:
- name: disks
  disk_size: 25_000

jobs:
- name: bosh
  templates:
  - {name: powerdns, release: bosh}
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
  - {name: private, static_ips: [10.0.0.10], default: [dns, gateway]}
  - {name: public, static_ips: [$DIRECTOR]}

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

    dns:
      address: $DIRECTOR
      db:
        user: postgres
        password: postgres-password
        host: 127.0.0.1
        listen_address: 127.0.0.1
        database: bosh
      user: powerdns
      password: powerdns
      database:
        name: powerdns
      webserver:
        password: powerdns
      replication:
        basic_auth: replication:zxKDUBeCfKYXk
        user: replication
        password: powerdns
      recursor: $DIRECTOR

    # Tells the Director/agents how to contact registry
    registry:
      address: 10.0.0.10
      host: 10.0.0.10
      db: *db
      http: {user: admin, password: admin, port: 25777}
      username: admin
      password: admin
      port: 25777

    # Tells the Director/agents how to contact blobstore
    blobstore:
      address: 10.0.0.10
      port: 25250
      provider: dav
      director: {user: director, password: director-password}
      agent: {user: agent, password: agent-password}

    director:
      address: 127.0.0.1
      name: bosh
      db: *db
      cpi_job: cpi
      enable_snapshots: true
      timeout: "180s"

    hm:
      http: {user: hm, password: hm-password}
      director_account: {user: admin, password: admin}

    azure: &azure
      environment: AzureCloud
      subscription_id: $AZURE_SUBSCRIPTION_ID
      storage_account_name: $AZURE_STORAGE_ACCOUNT_NAME
      storage_access_key: $AZURE_STORAGE_ACCESS_KEY
      resource_group_name: $AZURE_GROUP_NAME
      tenant_id: $AZURE_TENANT_ID
      client_id: $AZURE_CLIENT_ID
      client_secret: $AZURE_CLIENT_SECRET
      ssh_user: vcap
      ssh_certificate: | 
        $ssh_certificate

    # Tells agents how to contact nats
    agent: {mbus: "nats://nats:nats-password@10.0.0.10:4222"}

    ntp: &ntp [0.north-america.pool.ntp.org]

cloud_provider:
  template: {name: cpi, release: bosh-azure-cpi}

  # Tells bosh-init how to SSH into deployed VM
  ssh_tunnel:
    host: $DIRECTOR
    #host: 10.0.0.10
    port: 22
    user: vcap
    private_key: $manifest_dir/keys/bats.pem

  # Tells bosh-init how to contact remote agent
  mbus: https://mbus-user:mbus-password@$DIRECTOR:6868
#  mbus: https://mbus-user:mbus-password@10.0.0.10:6868

  properties:
    azure: *azure

    # Tells CPI how agent should listen for bosh-init requests
    agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}

    ntp: *ntp

EOF

echo "normalizing paths to match values referenced in $manifest_filename"
# manifest paths are now relative so the tmp inputs need to be updated
mkdir ${manifest_dir}/../tmp
echo copying cpi...
echo cp ./bosh-cpi-dev-artifacts/${cpi_release_name}-${semver}.tgz ${manifest_dir}/../tmp/${cpi_release_name}.tgz
cp ./bosh-cpi-dev-artifacts/${cpi_release_name}-${semver}.tgz ${manifest_dir}/../tmp/${cpi_release_name}.tgz
#cp ./bosh-release/release.tgz ${manifest_dir}/tmp/bosh-release.tgz ##TODO
#cp ./stemcell/stemcell.tgz ${manifest_dir}/tmp/stemcell.tgz ##TODO

initexe="$PWD/bosh-init/bosh-init-linux-amd64"
chmod +x $initexe

echo "using bosh-init CLI version..."
$initexe version

cat $manifest_filename
echo "deleting existing BOSH Director VM..."
$initexe delete $manifest_filename
#TODO: debug purpose, remove after this is official
export BOSH_INIT_LOG_LEVEL='Debug'
export BOSH_INIT_LOG_PATH='./run.log'
echo "deploying BOSH..."

$initexe deploy $manifest_filename
