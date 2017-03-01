#!/usr/bin/env bash

set -e

: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_GROUP_NAME_FOR_VMS:?}
: ${AZURE_GROUP_NAME_FOR_NETWORK:?}
: ${AZURE_VNET_NAME_FOR_BATS:?}
: ${AZURE_BOSH_SUBNET_NAME:?}
: ${AZURE_DEFAULT_SECURITY_GROUP:?}
: ${AZURE_DEBUG_MODE:?}
: ${SSH_PRIVATE_KEY:?}
: ${SSH_PUBLIC_KEY:?}
: ${BAT_NETWORK_GATEWAY:?}
: ${BOSH_DIRECTOR_USERNAME:?}
: ${BOSH_DIRECTOR_PASSWORD:?}
: ${BOSH_INIT_LOG_LEVEL:?}

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

DIRECTOR_PIP=$(azure network public-ip show ${AZURE_GROUP_NAME_FOR_NETWORK} AzureCPICI-bosh --json | jq '.ipAddress' -r)

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

semver=`cat version-semver/number`
cpi_release_name="bosh-azure-cpi"
output_dir=$(realpath director-state/)
ssh_key_path="${output_dir}/shared.pem"

# deployment manifest references releases and stemcells relative to itself...make it true
# these resources are also used in the teardown step
mkdir -p ${output_dir}/{stemcell,bosh-release,cpi-release}
cp ./stemcell/*.tgz ${output_dir}/stemcell/stemcell.tgz
cp ./bosh-release/release.tgz ${output_dir}/bosh-release/bosh-release.tgz
cp ./bosh-cpi-dev-artifacts/${cpi_release_name}-${semver}.tgz ${output_dir}/cpi-release/bosh-cpi.tgz

# env file generation
cat > "${output_dir}/director.env" <<EOF
#!/usr/bin/env bash
export BOSH_DIRECTOR_IP=${DIRECTOR_PIP}
export BOSH_DIRECTOR_USERNAME=${BOSH_DIRECTOR_USERNAME}
export BOSH_DIRECTOR_PASSWORD=${BOSH_DIRECTOR_PASSWORD}
EOF

manifest_filename="director.yml"
logfile=$(mktemp /tmp/bosh-init-log.XXXXXX)

echo "${SSH_PRIVATE_KEY}" > ${ssh_key_path}

if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
  cat > "${output_dir}/${manifest_filename}"<<EOF
---
name: bosh

releases:
- name: bosh
  url: file://bosh-release/bosh-release.tgz
- name: bosh-azure-cpi
  url: file://cpi-release/bosh-cpi.tgz
- name: os-conf
  url:  https://bosh.io/d/github.com/cloudfoundry/os-conf-release?v=11
  sha1: 651f10a765a2900a7f69ea07705f3367bd8041eb

networks:
- name: public
  type: vip
  cloud_properties:
    resource_group_name: ${AZURE_GROUP_NAME_FOR_NETWORK}
- name: private
  type: manual
  subnets:
  - range: 10.0.0.0/24
    gateway: 10.0.0.1
    dns: [168.63.129.16]
    cloud_properties:
      resource_group_name: ${AZURE_GROUP_NAME_FOR_NETWORK}
      virtual_network_name: ${AZURE_VNET_NAME_FOR_BATS}
      subnet_name: ${AZURE_BOSH_SUBNET_NAME}

resource_pools:
- name: vms
  network: private
  stemcell:
    url: file://stemcell/stemcell.tgz
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
  - {name: postgres, release: bosh}
  - {name: blobstore, release: bosh}
  - {name: director, release: bosh}
  - {name: health_monitor, release: bosh}
  - {name: registry, release: bosh}
  - {name: azure_cpi, release: bosh-azure-cpi}
  - {name: user_add, release: os-conf}

  instances: 1
  resource_pool: vms
  persistent_disk_pool: disks

  networks:
  - name: private
    static_ips: [10.0.0.10]
    default: [dns, gateway]
  - name: public
    static_ips: [${DIRECTOR_PIP}]

  properties:
    users:
    - name: cpidebug
      public_key: ${SSH_PUBLIC_KEY}

    nats:
      address: 127.0.0.1
      user: nats
      password: nats-password

    postgres: &db
      host: 127.0.0.1
      user: postgres
      password: postgres-password
      database: bosh
      adapter: postgres

    dns:
      address: ${DIRECTOR_PIP}
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
      recursor: 168.63.129.16

    # Tells the Director/agents how to contact registry
    registry:
      address: 10.0.0.10
      host: 10.0.0.10
      db: *db
      http: {user: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}, port: 25777}
      username: ${BOSH_DIRECTOR_USERNAME}
      password: ${BOSH_DIRECTOR_PASSWORD}
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
      cpi_job: azure_cpi
      enable_snapshots: true
      timeout: "180s"
      max_threads: 10
      user_management:
        provider: local
        local:
          users:
          - {name: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}}

    hm:
      http: {user: hm, password: hm-password}
      director_account: {user: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}}

    azure: &azure
      environment: AzureCloud
      subscription_id: ${AZURE_SUBSCRIPTION_ID}
      resource_group_name: ${AZURE_GROUP_NAME_FOR_VMS}
      tenant_id: ${AZURE_TENANT_ID}
      client_id: ${AZURE_CLIENT_ID}
      client_secret: ${AZURE_CLIENT_SECRET}
      ssh_user: vcap
      debug_mode: ${AZURE_DEBUG_MODE}
      ssh_public_key: ${SSH_PUBLIC_KEY}
      default_security_group: ${AZURE_DEFAULT_SECURITY_GROUP}
      use_managed_disks: true

    # Tells agents how to contact nats
    agent: {mbus: "nats://nats:nats-password@10.0.0.10:4222"}

    ntp: &ntp [0.north-america.pool.ntp.org]

cloud_provider:
  template: {name: azure_cpi, release: bosh-azure-cpi}

  # Tells bosh-init how to SSH into deployed VM
  ssh_tunnel:
    host: ${DIRECTOR_PIP}
    #host: 10.0.0.10
    port: 22
    user: vcap
    private_key: ${ssh_key_path}

  # Tells bosh-init how to contact remote agent
  mbus: https://mbus-user:mbus-password@${DIRECTOR_PIP}:6868

  properties:
    azure: *azure

    # Tells CPI how agent should listen for bosh-init requests
    agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}

    ntp: *ntp
EOF
else
  cat > "${output_dir}/${manifest_filename}"<<EOF
---
name: bosh

releases:
- name: bosh
  url: file://bosh-release/bosh-release.tgz
- name: bosh-azure-cpi
  url: file://cpi-release/bosh-cpi.tgz

networks:
- name: public
  type: vip
  cloud_properties:
    resource_group_name: ${AZURE_GROUP_NAME_FOR_NETWORK}
- name: private
  type: manual
  subnets:
  - range: 10.0.0.0/24
    gateway: 10.0.0.1
    dns: [168.63.129.16]
    cloud_properties:
      resource_group_name: ${AZURE_GROUP_NAME_FOR_NETWORK}
      virtual_network_name: ${AZURE_VNET_NAME_FOR_BATS}
      subnet_name: ${AZURE_BOSH_SUBNET_NAME}

resource_pools:
- name: vms
  network: private
  stemcell:
    url: file://stemcell/stemcell.tgz
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
  - {name: postgres, release: bosh}
  - {name: blobstore, release: bosh}
  - {name: director, release: bosh}
  - {name: health_monitor, release: bosh}
  - {name: registry, release: bosh}
  - {name: azure_cpi, release: bosh-azure-cpi}

  instances: 1
  resource_pool: vms
  persistent_disk_pool: disks

  networks:
  - name: private
    static_ips: [10.0.0.10]
    default: [dns, gateway]
  - name: public
    static_ips: [${DIRECTOR_PIP}]

  properties:
    nats:
      address: 127.0.0.1
      user: nats
      password: nats-password

    postgres: &db
      host: 127.0.0.1
      user: postgres
      password: postgres-password
      database: bosh
      adapter: postgres

    dns:
      address: ${DIRECTOR_PIP}
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
      recursor: 168.63.129.16

    # Tells the Director/agents how to contact registry
    registry:
      address: 10.0.0.10
      host: 10.0.0.10
      db: *db
      http: {user: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}, port: 25777}
      username: ${BOSH_DIRECTOR_USERNAME}
      password: ${BOSH_DIRECTOR_PASSWORD}
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
      cpi_job: azure_cpi
      enable_snapshots: true
      timeout: "180s"
      max_threads: 10
      user_management:
        provider: local
        local:
          users:
          - {name: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}}

    hm:
      http: {user: hm, password: hm-password}
      director_account: {user: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}}

    azure: &azure
      environment: AzureCloud
      subscription_id: ${AZURE_SUBSCRIPTION_ID}
      storage_account_name: ${AZURE_STORAGE_ACCOUNT_NAME}
      resource_group_name: ${AZURE_GROUP_NAME_FOR_VMS}
      tenant_id: ${AZURE_TENANT_ID}
      client_id: ${AZURE_CLIENT_ID}
      client_secret: ${AZURE_CLIENT_SECRET}
      ssh_user: vcap
      debug_mode: ${AZURE_DEBUG_MODE}
      ssh_public_key: ${SSH_PUBLIC_KEY}
      default_security_group: ${AZURE_DEFAULT_SECURITY_GROUP}

    # Tells agents how to contact nats
    agent: {mbus: "nats://nats:nats-password@10.0.0.10:4222"}

    ntp: &ntp [0.north-america.pool.ntp.org]

cloud_provider:
  template: {name: azure_cpi, release: bosh-azure-cpi}

  # Tells bosh-init how to SSH into deployed VM
  ssh_tunnel:
    host: ${DIRECTOR_PIP}
    #host: 10.0.0.10
    port: 22
    user: vcap
    private_key: ${ssh_key_path}

  # Tells bosh-init how to contact remote agent
  mbus: https://mbus-user:mbus-password@${DIRECTOR_PIP}:6868

  properties:
    azure: *azure

    # Tells CPI how agent should listen for bosh-init requests
    agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}

    ntp: *ntp
EOF
fi

function finish {
  echo "Final state of director deployment:"
  echo "=========================================="
  cat "${output_dir}/director-state.json"
  echo "=========================================="

  cp -r ${HOME}/.bosh_init ${output_dir}
  rm -rf ${logfile}
}
trap finish EXIT

bosh_init=$(realpath bosh-init/bosh-init-*)
chmod +x ${bosh_init}

echo "using bosh-init CLI version..."
${bosh_init} version

pushd ${output_dir} > /dev/null
  echo "deploying BOSH..."

  set +e
  BOSH_INIT_LOG_PATH="${logfile}" BOSH_INIT_LOG_LEVEL="${BOSH_INIT_LOG_LEVEL}" ${bosh_init} deploy ${manifest_filename}
  bosh_init_exit_code="$?"
  set -e

  if [ ${bosh_init_exit_code} != 0 ]; then
    echo "bosh-init deploy failed!" >&2
    cat ${logfile} >&2
    exit ${bosh_init_exit_code}
  fi
popd > /dev/null
