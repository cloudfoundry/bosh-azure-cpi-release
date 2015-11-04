#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh
source azure-exports/azure-exports.sh
check_param base_os
check_param private_key_data
check_param BAT_VCAP_PASSWORD
check_param BAT_SECOND_STATIC_IP
check_param BAT_NETWORK_CIDR
check_param BAT_NETWORK_RESERVED_RANGE
check_param BAT_NETWORK_STATIC_RANGE
check_param BAT_NETWORK_GATEWAY
check_param BAT_NETWORK_STATIC_IP
check_param BAT_STEMCELL_URL
check_param BAT_STEMCELL_SHA
check_param AZURE_VNET_NAME
check_param AZURE_CF_SUBNET_NAME
check_param CF_IP_ADDRESS
#TODO: debug purpose, remove after this is official
export LOG_LEVEL='Debug'
export LOG_PATH='./run.log'
source /etc/profile.d/chruby.sh
chruby 2.1.2



echo "DirectorIP =" $DIRECTOR

mkdir -p $PWD/keys
echo "$private_key_data" > $PWD/keys/bats.pem
eval $(ssh-agent)
chmod go-r $PWD/keys/bats.pem
ssh-add $PWD/keys/bats.pem

export BAT_DIRECTOR=$DIRECTOR
export BAT_DNS_HOST=$DIRECTOR
export BAT_STEMCELL="${PWD}/stemcell/stemcell.tgz"
export BAT_DEPLOYMENT_SPEC="${PWD}/${base_os}-bats-config.yml"
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
    version: '0000'
  vip: $CF_IP_ADDRESS
  pool_size: 1
  instances: 1
  second_static_ip: $BAT_SECOND_STATIC_IP
  networks:
  - name: default
    type: manual
    static_ip: $BAT_NETWORK_STATIC_IP
    cloud_properties:
      virtual_network_name: $AZURE_VNET_NAME
      subnet_name: $AZURE_CF_SUBNET_NAME
    cidr: $BAT_NETWORK_CIDR
    reserved: ['$BAT_NETWORK_RESERVED_RANGE']
    static: ['$BAT_NETWORK_STATIC_RANGE']
    gateway: $BAT_NETWORK_GATEWAY
  - name: static
    type: vip
    cloud_properties:
      tcp_endpoints:
      - "22:22"
      - "80:80"
      - "443:443"
      - "4222:4222"
      - "4443:4443"
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
  <% else %>
  cloud_properties:
    <% if network.cloud_properties.tcp_endpoints %>
    tcp_endpoints:
      <% network.cloud_properties.tcp_endpoints.each do |endpoint| %>
      - "<%= endpoint %>"
      <% end %>
    <% end %>
    <% if network.cloud_properties.udp_endpoints %>
    udp_endpoints:
      <% network.cloud_properties.udp_endpoints.each do |endpoint| %>
      - "<%= endpoint %>"
      <% end %>
    <% end %>
    <% if !network.cloud_properties.tcp_endpoints && !network.cloud_properties.tcp_endpoints %>
      {}
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
echo Using Deployment Spec:
cat $BAT_DEPLOYMENT_SPEC
cd bosh
ls
# THIS WILL GO AWAY AFTER BATS CODE IS MERGED
rm .gitmodules
cat > ".gitmodules" <<EOF
[submodule "go/src/github.com/cloudfoundry/bosh-agent"]
      path = go/src/github.com/cloudfoundry/bosh-agent
      url = https://github.com/AbelHu/bosh-agent.git
      branch = abelhu
[submodule "spec/assets/uaa"]
      path = spec/assets/uaa
      url = https://github.com/cloudfoundry/uaa.git
[submodule "bat"]
      path = bat
      url = https://github.com/AbelHu/bosh-acceptance-tests.git
      branch = abelhu
[submodule "go/src/github.com/cloudfoundry/bosh-davcli"]
      path = go/src/github.com/cloudfoundry/bosh-davcli
      url = https://github.com/cloudfoundry/bosh-davcli.git
EOF
pwd
echo cat .gitmodules
cat .gitmodules
rm .git/config
cat > ".git/config" <<EOF
[core]
  repositoryformatversion = 0
  filemode = true
  bare = false
  logallrefupdates = true
[remote "origin"]
  url = https://github.com/AbelHu/bosh
  fetch = +refs/heads/*:refs/remotes/origin/*
[submodule "bat"]
  url = https://github.com/AbelHu/bosh-acceptance-tests.git
  branch = master
[submodule "go/src/github.com/cloudfoundry/bosh-agent"]
  url = https://github.com/AbelHu/bosh-agent.git
  branch = abelhu
[submodule "spec/assets/uaa"]
  url = https://github.com/cloudfoundry/uaa.git
EOF
cd bat
git config remote.origin.url https://github.com/AbelHu/bosh-acceptance-tests.git
cd ..
pushd go/src/github.com/cloudfoundry/bosh-agent
git config remote.origin.url https://github.com/AbelHu/bosh-agent.git
popd
echo Current Directory:
echo git submodule update --init
git submodule update --init
echo git submodule update --remote
git submodule update --remote
#gem uninstall mini_portile -v '0.7.0.rc2' --ignore-dependencies
#gem install mini_portile -v '0.6.2'
echo bundle install
bundle install
echo bundle exec rake bat:env
bundle exec rake bat:env
echo bundle exec rake bat
bundle exec rake bat