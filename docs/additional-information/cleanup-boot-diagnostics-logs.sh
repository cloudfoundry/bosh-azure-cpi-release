#!/usr/bin/env bash

set -e

function usage() {
  echo "Warning: This script will try to delete all VM diagnostics logs that were created by Azure CPI v35.2.0+"
  echo "         The logs are in containers which:"
  echo "         - has the name starting with bootdiagnostics-*, and"
  echo "         - is resident in the storage account with tags {\"user-agent\": \"bosh\", \"type\": \"bootdiagnostics\"}"
  echo ""
  echo ""
  echo "Please make sure you have az (azure cli v2) and jq installed;"
  echo "       and input a valid resource group name."
  echo ""
  echo "Usage: bash $0 <resource-group-name>"
  echo ""
}

function cleanup_boot_diag_logs_from_storage_account() {
  storage_account_name=$1
  echo "Cleaning up boot diagnostics logs from storage account $storage_account_name"
  connection_string=$(az storage account show-connection-string --resource-group $resource_group --name $storage_account_name | jq .connectionString --raw-output)
  containers=$(az storage container list --connection-string $connection_string | jq '.[] .name' --raw-output | grep ^bootdiagnostics-)

  # set to +e to ignore errors
  set +e
  for container in $containers; do
    if [[ $container  == bootdiagnostics-* ]]; then
      echo "Deleting container $container"
      az storage container delete --name $container --connection-string "$connection_string"
      if [[ $? == 0 ]];then
        echo "Deleted: $container"
      else
        echo "Not delete: $container - There might be leases on the container. Ignore!"
      fi
    fi
  done
  set -e
}

function cleanup_boot_diag_logs_from_resource_group() {
  resource_group=$1

  # find storage accounts used for boot diagnostics
  storage_account_names=$(az storage account list -g $resource_group | jq '.[] | select(.tags.type=="bootdiagnostics") | select(.tags."user-agent"=="bosh")' | jq .name --raw-output)

  # cleanup containers from storage accounts
  for storage_account_name in $storage_account_names; do
    cleanup_boot_diag_logs_from_storage_account $storage_account_name
  done
}

if [[ $# -ne 1 ]]; then
  usage
  exit -1
fi

cleanup_boot_diag_logs_from_resource_group $1
