#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_TENANT_ID
check_param AZURE_GROUP_NAME
check_param AZURE_STORAGE_ACCOUNT_NAME
check_param AZURE_SUBSCRIPTION_ID
check_param SSH_CERTIFICATE
check_param AZURE_VNET_NAME_FOR_LIFECYCLE
check_param AZURE_BOSH_SUBNET_NAME

export BOSH_AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME}
export BOSH_AZURE_RESOURCE_GROUP_NAME=${AZURE_GROUP_NAME}
export BOSH_AZURE_TENANT_ID=${AZURE_TENANT_ID}
export BOSH_AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export BOSH_AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export BOSH_AZURE_VNET_NAME=${AZURE_VNET_NAME_FOR_LIFECYCLE}
export BOSH_AZURE_SUBNET_NAME=${AZURE_BOSH_SUBNET_NAME}

source /etc/profile.d/chruby.sh
chruby 2.1.2

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

AZURE_STORAGE_ACCESS_KEY=$(azure storage account keys list ${AZURE_STORAGE_ACCOUNT_NAME} -g ${AZURE_GROUP_NAME} --json | jq '.storageAccountKeys.key1' -r)

export BOSH_AZURE_STEMCELL_ID="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
export AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT_NAME}
export AZURE_STORAGE_ACCESS_KEY

# Upload stemcell if it does not exist.
# Lifycycle is used to test CPI but not stemcell so you can use any valid stemcell.
set +e
azure storage blob show stemcell ${BOSH_AZURE_STEMCELL_ID}.vhd
if [ $? -eq 1 ]; then
  # Upload stemcell
  tar -xf "${PWD}/stemcell/stemcell.tgz" -C /mnt/
  tar -xf /mnt/image -C /mnt/
  azure storage blob upload -q --blobtype PAGE /mnt/root.vhd stemcell ${BOSH_AZURE_STEMCELL_ID}.vhd
fi
set -e

echo write cert to file
echo "$SSH_CERTIFICATE" > /tmp/azurecert
echo cert written to file
tail -n1 /tmp/azurecert
export BOSH_AZURE_CERTIFICATE_FILE="/tmp/azurecert"

cd bosh-cpi-release/src/bosh_azure_cpi

bundle install
bundle exec rspec spec/integration