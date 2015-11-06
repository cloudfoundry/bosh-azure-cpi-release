#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_TENANT_ID
check_param AZURE_GROUP_NAME
check_param AZURE_STORAGE_ACCOUNT_NAME
check_param AZURE_SUBSCRIPTION_ID
check_param BAT_STEMCELL_URL
check_param ssh_certificate
check_param AZURE_VNET_NAME
check_param AZURE_BOSH_SUBNET_NAME

export LOG_LEVEL='Debug'
export LOG_PATH='./run.log'

export BOSH_AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME}
export BOSH_AZURE_RESOURCE_GROUP_NAME=${AZURE_GROUP_NAME}
export BOSH_AZURE_TENANT_ID=${AZURE_TENANT_ID}
export BOSH_AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export BOSH_AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export BOSH_AZURE_VNET_NAME=${AZURE_VNET_NAME}
export BOSH_AZURE_SUBNET_NAME=${AZURE_BOSH_SUBNET_NAME}

source /etc/profile.d/chruby.sh
chruby 2.1.2

export BOSH_AZURE_STEMCELL_FILE="${PWD}/stemcell/stemcell.tgz"
echo $BOSH_AZURE_STEMCELL_FILE

echo write cert to file
echo "$ssh_certificate" > /tmp/azurecert
echo cert written to file
tail -n1 /tmp/azurecert
export BOSH_AZURE_CERTIFICATE_FILE="/tmp/azurecert"

cd bosh-cpi-release/src/bosh_azure_cpi

bundle install
bundle exec rspec spec/integration