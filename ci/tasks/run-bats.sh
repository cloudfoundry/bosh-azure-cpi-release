#!/usr/bin/env bash

set -e

: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_GROUP_NAME:?}
: ${AZURE_VNET_NAME_FOR_BATS:?}
: ${AZURE_CF_SUBNET_NAME:?}
: ${AZURE_CF_SECOND_SUBNET_NAME:?}
: ${AZURE_DEFAULT_SECURITY_GROUP:?}
: ${BAT_VCAP_PASSWORD:?}
: ${BAT_NETWORK_CIDR:?}
: ${BAT_SECOND_NETWORK_CIDR:?}
: ${BAT_SECOND_STATIC_IP:?}             # static ip for the first subnet
: ${BAT_NETWORK_RESERVED_RANGE:?}
: ${BAT_SECOND_NETWORK_RESERVED_RANGE:?}
: ${BAT_NETWORK_STATIC_RANGE:?}
: ${BAT_SECOND_NETWORK_STATIC_RANGE:?}
: ${BAT_NETWORK_GATEWAY:?}
: ${BAT_SECOND_NETWORK_GATEWAY:?}
: ${BAT_NETWORK_STATIC_IP:?}            # static ip for the first subnet
: ${BAT_SECOND_NETWORK_STATIC_IP:?}     # static ip for the second subnet
: ${BAT_BASE_OS:?}
: ${BOSH_DIRECTOR_USERNAME:?}
: ${BOSH_DIRECTOR_PASSWORD:?}
: ${SSH_PRIVATE_KEY:?}

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

DIRECTOR_PIP=$(azure network public-ip show ${AZURE_GROUP_NAME} AzureCPICI-bosh --json | jq '.ipAddress' -r)
CF_IP_ADDRESS=$(azure network public-ip show ${AZURE_GROUP_NAME} AzureCPICI-cf-bats --json | jq '.ipAddress' -r)

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

work_dir=$(realpath .)
bats_stemcell=$(realpath stemcell/*.tgz)
bats_spec="${work_dir}/bats-config.yml"
ssh_key_path="${work_dir}/shared.pem"
bats_template="${work_dir}/azure.yml.erb"

cat > "${bats_template}" <<EOF
---
name: <%= properties.name || "bat" %>
director_uuid: <%= properties.uuid %>

releases:
  - name: bat
    version: <%= properties.release || "latest" %>

compilation:
  workers: 2
  network: default
  reuse_compilation_vms: true
  cloud_properties:
    instance_type: Standard_D3_v2
    <% if properties.key_name %>
    key_name: <%= properties.key_name %>
    <% end %>

update:
  canaries: <%= properties.canaries || 1 %>
  canary_watch_time: 3000-90000
  update_watch_time: 3000-90000
  max_in_flight: <%= properties.max_in_flight || 1 %>

networks:
<% properties.networks.each do |network| %>
- name: <%= network.name %>
  type: <%= network.type %>
  <% if network.type == 'manual' %>
  subnets:
  - range: <%= network.cidr %>
    reserved:
      <% network.reserved.each do |range| %>
      - <%= range %>
      <% end %>
    static:
      <% network.static.each do |range| %>
      - <%= range %>
      <% end %>
    gateway: <%= network.gateway %>
    dns: <%= p('dns').inspect %>
    cloud_properties:
      <% if network.cloud_properties.resource_group_name %>
      resource_group_name: <%= network.cloud_properties.resource_group_name %>
      <% end %>
      virtual_network_name: <%= network.cloud_properties.virtual_network_name %>
      subnet_name: <%= network.cloud_properties.subnet_name %>
      <% if network.cloud_properties.security_group %>
      security_group: <%= network.cloud_properties.security_group %>
      <% end %>
  <% elsif network.type == 'dynamic' %>
  subnets:
  - range: <%= network.cidr %>
    dns: <%= p('dns').inspect %>
    cloud_properties:
      <% if network.cloud_properties.resource_group_name %>
      resource_group_name: <%= network.cloud_properties.resource_group_name %>
      <% end %>
      virtual_network_name: <%= network.cloud_properties.virtual_network_name %>
      subnet_name: <%= network.cloud_properties.subnet_name %>
      <% if network.cloud_properties.security_group %>
      security_group: <%= network.cloud_properties.security_group %>
      <% end %>
  <% elsif network.type == 'vip' %>
  <% if network.cloud_properties.resource_group_name %>
  cloud_properties:
    resource_group_name: <%= network.cloud_properties.resource_group_name %>
  <% end %>
  <% end %>
<% end %>

resource_pools:
  - name: common
    network: default
    size: <%= properties.pool_size %>
    stemcell:
      name: <%= properties.stemcell.name %>
      version: '<%= properties.stemcell.version %>'
    cloud_properties:
      instance_type: Standard_D3_v2
      <% if properties.key_name %>
      key_name: <%= properties.key_name %>
      <% end %>
    <% if properties.password %>
    env:
      bosh:
        password: <%= properties.password %>
    <% end %>

jobs:
  - name: <%= properties.job || "batlight" %>
    templates: <% (properties.templates || ["batlight"]).each do |template| %>
    - name: <%= template %>
    <% end %>
    instances: <%= properties.instances %>
    resource_pool: common
    <% if properties.persistent_disk %>
    persistent_disk: <%= properties.persistent_disk %>
    <% end %>
    networks:
    <% properties.job_networks.each_with_index do |network, i| %>
      - name: <%= network.name %>
        <% if i == 0 %>
        default: [dns, gateway]
        <% end %>
      <% if network.type == 'manual' %>
        static_ips:
        <% if properties.use_static_ip %>
        - <%= network.static_ip %>
        <% end %>
      <% end %>
    <% end %>
    <% if properties.use_vip %>
      - name: static
        static_ips:
          - <%= properties.vip %>
    <% end %>

properties:
  batlight:
    <% if properties.batlight.fail %>
    fail: <%= properties.batlight.fail %>
    <% end %>
    <% if properties.batlight.missing %>
    missing: <%= properties.batlight.missing %>
    <% end %>
    <% if properties.batlight.drain_type %>
    drain_type: <%= properties.batlight.drain_type %>
    <% end %>
EOF

echo "DirectorIP = " ${DIRECTOR_PIP}

echo "${SSH_PRIVATE_KEY}" > ${ssh_key_path}
chmod go-r ${ssh_key_path}
eval $(ssh-agent)
ssh-add ${ssh_key_path}

export BAT_DIRECTOR=${DIRECTOR_PIP}
export BAT_DNS_HOST=${DIRECTOR_PIP}
export BAT_STEMCELL=${bats_stemcell}
export BAT_DEPLOYMENT_SPEC=${bats_spec}
export BAT_VCAP_PASSWORD=${BAT_VCAP_PASSWORD}
export BAT_VCAP_PRIVATE_KEY=${ssh_key_path}
export BAT_INFRASTRUCTURE=azure
export BAT_NETWORKING=manual
export BAT_DIRECTOR_USER=${BOSH_DIRECTOR_USERNAME}
export BAT_DIRECTOR_PASSWORD=${BOSH_DIRECTOR_PASSWORD}
export BAT_RSPEC_FLAGS="--tag ~raw_ephemeral_storage"

# multiple_manual_networks fails due to the issue described in https://github.com/cloudfoundry/bosh/pull/1457. Once it's merged, the tag should be removed.
if [ "${BAT_BASE_OS}" == "centos-7" ]; then
  export BAT_RSPEC_FLAGS="--tag ~raw_ephemeral_storage --tag ~multiple_manual_networks"
fi

bosh -n target ${BAT_DIRECTOR}
echo Using This version of bosh:
bosh --version

cat > "${BAT_DEPLOYMENT_SPEC}" <<EOF
---
cpi: azure
manifest_template_path: ${bats_template}
properties:
  uuid: $(bosh status --uuid)
  stemcell:
    name: bosh-azure-hyperv-${BAT_BASE_OS}-go_agent
    version: latest
  vip: ${CF_IP_ADDRESS}
  pool_size: 1
  instances: 1
  second_static_ip: ${BAT_SECOND_STATIC_IP}
  networks:
  - name: default
    type: manual
    static_ip: ${BAT_NETWORK_STATIC_IP}
    cloud_properties:
      resource_group_name: ${AZURE_GROUP_NAME}
      virtual_network_name: ${AZURE_VNET_NAME_FOR_BATS}
      subnet_name: ${AZURE_CF_SUBNET_NAME}
      security_group: ${AZURE_DEFAULT_SECURITY_GROUP}
    cidr: ${BAT_NETWORK_CIDR}
    reserved: [${BAT_NETWORK_RESERVED_RANGE}]
    static: [${BAT_NETWORK_STATIC_RANGE}]
    gateway: ${BAT_NETWORK_GATEWAY}
  - name: second
    type: manual
    static_ip: ${BAT_SECOND_NETWORK_STATIC_IP}
    cloud_properties:
      resource_group_name: ${AZURE_GROUP_NAME}
      virtual_network_name: ${AZURE_VNET_NAME_FOR_BATS}
      subnet_name: ${AZURE_CF_SECOND_SUBNET_NAME}
      security_group: ${AZURE_DEFAULT_SECURITY_GROUP}
    cidr: ${BAT_SECOND_NETWORK_CIDR}
    reserved: [${BAT_SECOND_NETWORK_RESERVED_RANGE}]
    static: [${BAT_SECOND_NETWORK_STATIC_RANGE}]
    gateway: ${BAT_SECOND_NETWORK_GATEWAY}
  - name: static
    type: vip
    cloud_properties:
      resource_group_name: ${AZURE_GROUP_NAME}
  key_name: bosh
EOF

pushd bats > /dev/null
  ./write_gemfile
  bundle install
  bundle exec rspec spec ${BAT_RSPEC_FLAGS}
popd > /dev/null
