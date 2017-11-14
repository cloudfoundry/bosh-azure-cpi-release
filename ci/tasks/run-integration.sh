#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${SSH_PUBLIC_KEY:?}
: ${AZURE_APPLICATION_GATEWAY_NAME:?}
: ${AZURE_APPLICATION_SECURITY_GROUP_NAME:?}

: ${METADATA_FILE:=environment/metadata}

metadata=$(cat ${METADATA_FILE})

export BOSH_AZURE_ENVIRONMENT=${AZURE_ENVIRONMENT}
export BOSH_AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export BOSH_AZURE_TENANT_ID=${AZURE_TENANT_ID}
export BOSH_AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export BOSH_AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME=$(echo ${metadata} | jq -e --raw-output ".default_resource_group_name")
export BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME=$(echo ${metadata} | jq -e --raw-output ".additional_resource_group_name")
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=$(echo ${metadata} | jq -e --raw-output ".storage_account_name")
export BOSH_AZURE_EXTRA_STORAGE_ACCOUNT_NAME=$(echo ${metadata} | jq -e --raw-output ".extra_storage_account_name")
export BOSH_AZURE_VNET_NAME=$(echo ${metadata} | jq -e --raw-output ".vnet_name")
export BOSH_AZURE_SUBNET_NAME=$(echo ${metadata} | jq -e --raw-output ".subnet_1_name")
export BOSH_AZURE_SECOND_SUBNET_NAME=$(echo ${metadata} | jq -e --raw-output ".subnet_2_name")
export BOSH_AZURE_DEFAULT_SECURITY_GROUP=$(echo ${metadata} | jq -e --raw-output ".default_security_group")
export BOSH_AZURE_PRIMARY_PUBLIC_IP=$(echo ${metadata} | jq -e --raw-output ".public_ip_in_default_rg")
export BOSH_AZURE_SECONDARY_PUBLIC_IP=$(echo ${metadata} | jq -e --raw-output ".public_ip_in_additional_rg")
export BOSH_AZURE_SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export BOSH_AZURE_APPLICATION_GATEWAY_NAME=${AZURE_APPLICATION_GATEWAY_NAME}
export BOSH_AZURE_APPLICATION_SECURITY_GROUP=${AZURE_APPLICATION_SECURITY_GROUP_NAME}

az cloud set --name ${AZURE_ENVIRONMENT}
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
az account set -s ${AZURE_SUBSCRIPTION_ID}

export BOSH_AZURE_STEMCELL_ID="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
export BOSH_AZURE_STEMCELL_PATH="/tmp/image"
account_name=${BOSH_AZURE_STORAGE_ACCOUNT_NAME}
account_key=$(az storage account keys list --account-name ${account_name} --resource-group ${BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME} | jq '.[0].value' -r)
# Always upload the latest stemcell for lifecycle test
tar -xf $(realpath stemcell/*.tgz) -C /tmp/
tar -xf ${BOSH_AZURE_STEMCELL_PATH} -C /tmp/
az storage blob upload --file /tmp/root.vhd --container-name stemcell --name ${BOSH_AZURE_STEMCELL_ID}.vhd --type page --account-name ${account_name} --account-key ${account_key}

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

pushd bosh-cpi-src/src/bosh_azure_cpi > /dev/null
  bundle install

  export BOSH_AZURE_USE_MANAGED_DISKS=${AZURE_USE_MANAGED_DISKS}
  if [ "${AZURE_USE_MANAGED_DISKS}" == "false" ]; then
    bundle exec rspec spec/integration/lifecycle_spec.rb --tag ~light_stemcell
  else
    bundle exec rspec spec/integration/lifecycle_spec.rb --tag ~light_stemcell --tag ~unmanaged_disks
  fi

  # Only run migration test when AZURE_USE_MANAGED_DISKS is set to false initially
  if [ "${AZURE_USE_MANAGED_DISKS}" == "false" ]; then
    unset BOSH_AZURE_USE_MANAGED_DISKS
    bundle exec rspec spec/integration/managed_disks_migration_spec.rb
  fi
  
  # The azure_cpi test doesn't care whether managed disks are used. Only run it when AZURE_USE_MANAGED_DISKS is set to true
  if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
    export BOSH_AZURE_USE_MANAGED_DISKS=true
    bundle exec rspec spec/integration/azure_cpi_spec.rb
  fi
popd > /dev/null
