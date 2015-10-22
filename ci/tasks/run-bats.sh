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