#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_CERTIFICATE:?}
: ${SSH_PUBLIC_KEY:?}

: ${METADATA_FILE:=environment/metadata}

metadata=$(cat ${METADATA_FILE})

export BOSH_AZURE_ENVIRONMENT=${AZURE_ENVIRONMENT}
export BOSH_AZURE_TENANT_ID=${AZURE_TENANT_ID}
export BOSH_AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export BOSH_AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export BOSH_AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export BOSH_AZURE_CERTIFICATE=${AZURE_CERTIFICATE}
export BOSH_AZURE_LOCATION=$(echo ${metadata} | jq -e --raw-output ".location")
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
export BOSH_AZURE_APPLICATION_SECURITY_GROUP=$(echo ${metadata} | jq -e --raw-output ".asg_name")
export BOSH_AZURE_APPLICATION_GATEWAY_NAME=$(echo ${metadata} | jq -e --raw-output ".application_gateway_name")
export BOSH_AZURE_SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}

export BOSH_AZURE_STEMCELL_PATH=$(realpath stemcell/*.tgz)

source stemcell-state/stemcell.env
source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

pushd bosh-cpi-src/src/bosh_azure_cpi > /dev/null
  bundle install

  tags="--tag ~light_stemcell"
  export BOSH_AZURE_USE_MANAGED_DISKS=${AZURE_USE_MANAGED_DISKS}
  if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
    tags+=" --tag ~unmanaged_disks"
  else
    tags+=" --tag ~availability_zone"
  fi
  bundle exec rspec spec/integration/lifecycle_spec.rb ${tags}

  # migration: unmanged disk -> managed disk
  # Only run migration test when AZURE_USE_MANAGED_DISKS is set to false initially
  if [ "${AZURE_USE_MANAGED_DISKS}" == "false" ]; then
    unset BOSH_AZURE_USE_MANAGED_DISKS
    bundle exec rspec spec/integration/managed_disks_migration_spec.rb
  fi

  # migration: regional resource -> zonal resource
  # Only run migration test when AZURE_USE_MANAGED_DISKS is set to true initially
  if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
    export BOSH_AZURE_USE_MANAGED_DISKS=true
    bundle exec rspec spec/integration/availability_zone_migration_spec.rb
  fi
  
  # The azure_cpi test doesn't care whether managed disks are used. Only run it when AZURE_USE_MANAGED_DISKS is set to true
  if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
    export BOSH_AZURE_USE_MANAGED_DISKS=true
    bundle exec rspec spec/integration/azure_cpi_spec.rb
  fi
popd > /dev/null
