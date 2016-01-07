#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_GROUP_NAME
check_param AZURE_REGION_NAME
check_param AZURE_REGION_SHORT_NAME
check_param AZURE_TENANT_ID
check_param AZURE_VNET_NAME_FOR_BATS
check_param AZURE_VNET_NAME_FOR_LIFECYCLE
check_param AZURE_BOSH_SUBNET_NAME
check_param AZURE_CF_SUBNET_NAME

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

set +e

# check if group already exists
echo "azure group list | grep ${AZURE_GROUP_NAME}"
azure group list | grep ${AZURE_GROUP_NAME}

if [ $? -eq 0 ]
then
  echo "azure group delete ${AZURE_GROUP_NAME}"
  azure group delete ${AZURE_GROUP_NAME} --quiet
  echo "waiting for delete operation to finish..."
  # wait for resource group to delet 
  azure group show ${AZURE_GROUP_NAME}
  while [ $? -eq 0 ]
  do
    azure group show ${AZURE_GROUP_NAME} > /dev/null 2>&1
    echo "..."
  done
fi

set -e

echo azure group create ${AZURE_GROUP_NAME} ${AZURE_REGION_SHORT_NAME}
azure group create ${AZURE_GROUP_NAME} ${AZURE_REGION_SHORT_NAME}
echo "{ \"location\": { \"value\": \"${AZURE_REGION_NAME}\" }, \"newStorageAccountName\": { \"value\": \"${AZURE_STORAGE_ACCOUNT_NAME}\" }, \"virtualNetworkNameForBats\": { \"value\": \"${AZURE_VNET_NAME_FOR_BATS}\" }, \"virtualNetworkNameForLifecycle\": { \"value\": \"${AZURE_VNET_NAME_FOR_LIFECYCLE}\" }, \"subnetNameForBosh\": { \"value\": \"${AZURE_BOSH_SUBNET_NAME}\" }, \"subnetNameForCloudFoundry\": { \"value\": \"${AZURE_CF_SUBNET_NAME}\" } }" > provision-parameters.json
azure group deployment create ${AZURE_GROUP_NAME} --template-file ./bosh-cpi-release/ci/assets/azure/provision.json --parameters-file ./provision-parameters.json

#setup storage account containers
AZURE_ACCOUNT_KEY=$(azure storage account keys list ${AZURE_STORAGE_ACCOUNT_NAME} -g ${AZURE_GROUP_NAME} --json | jq '.storageAccountKeys.key1' -r)
azure storage container create --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container bosh
azure storage container create --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} -p blob --container stemcell
