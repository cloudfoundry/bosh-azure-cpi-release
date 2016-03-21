#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param BASE_OS
check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_TENANT_ID
check_param AZURE_GROUP_NAME
check_param SSH_PRIVATE_KEY
check_param BAT_VCAP_PASSWORD
check_param BAT_SECOND_STATIC_IP
check_param BAT_NETWORK_CIDR
check_param BAT_NETWORK_RESERVED_RANGE
check_param BAT_NETWORK_STATIC_RANGE
check_param BAT_NETWORK_GATEWAY
check_param BAT_NETWORK_STATIC_IP
check_param BAT_STEMCELL_URL
check_param BAT_STEMCELL_SHA
check_param AZURE_VNET_NAME_FOR_BATS
check_param AZURE_CF_SUBNET_NAME

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

DIRECTOR=$(azure network public-ip show ${AZURE_GROUP_NAME} AzureCPICI-bosh --json | jq '.ipAddress' -r)
CF_IP_ADDRESS=$(azure network public-ip show ${AZURE_GROUP_NAME} AzureCPICI-cf --json | jq '.ipAddress' -r)

source /etc/profile.d/chruby.sh
chruby 2.1.2

echo "DirectorIP =" $DIRECTOR

mkdir -p $PWD/keys
echo "$SSH_PRIVATE_KEY" > $PWD/keys/bats.pem
eval $(ssh-agent)
chmod go-r $PWD/keys/bats.pem
ssh-add $PWD/keys/bats.pem

export BAT_DIRECTOR=$DIRECTOR
export BAT_DNS_HOST=$DIRECTOR
export BAT_STEMCELL=`echo $PWD/stemcell/*.tgz`
export BAT_DEPLOYMENT_SPEC="${PWD}/${BASE_OS}-bats-config.yml"
export BAT_VCAP_PASSWORD=$BAT_VCAP_PASSWORD
export BAT_VCAP_PRIVATE_KEY=$PWD/keys/bats.pem
export BAT_INFRASTRUCTURE=azure
export BAT_NETWORKING=manual

bosh -n target $BAT_DIRECTOR
echo Using This version of bosh:
bosh --version
cat > "${BAT_DEPLOYMENT_SPEC}" <<EOF
---
cpi: azure
manifest_template_path: $(echo `pwd`/azure.yml.erb)
properties:
  uuid: $(bosh status --uuid)
  stemcell:
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  vip: $CF_IP_ADDRESS
  pool_size: 1
  instances: 1
  second_static_ip: $BAT_SECOND_STATIC_IP
  networks:
  - name: default
    type: manual
    static_ip: $BAT_NETWORK_STATIC_IP
    cloud_properties:
      virtual_network_name: $AZURE_VNET_NAME_FOR_BATS
      subnet_name: $AZURE_CF_SUBNET_NAME
    cidr: $BAT_NETWORK_CIDR
    reserved: ['$BAT_NETWORK_RESERVED_RANGE']
    static: ['$BAT_NETWORK_STATIC_RANGE']
    gateway: $BAT_NETWORK_GATEWAY
  - name: static
    type: vip
  key_name: bosh
EOF
cat > azure.yml.erb <<EOF
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
    instance_type: Standard_A1
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
      virtual_network_name: <%= network.cloud_properties.virtual_network_name %>
      subnet_name: <%= network.cloud_properties.subnet_name %>
  <% elsif network.type == 'dynamic' %>
  subnets:
  - range: <%= network.cidr %>
    dns: <%= p('dns').inspect %>
  cloud_properties:
    virtual_network_name: <%= network.cloud_properties.virtual_network_name %>
    subnet_name: <%= network.cloud_properties.subnet_name %>
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
      instance_type: Standard_A1
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
        default: [dns, gateway]
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

cd bats
./write_gemfile
bundle install
bundle exec rspec spec