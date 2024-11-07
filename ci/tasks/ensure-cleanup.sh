#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}

: ${METADATA_FILE:=environment/metadata}

az cloud set --name ${AZURE_ENVIRONMENT}
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
az account set -s ${AZURE_SUBSCRIPTION_ID}

# In most cases, terraform can destroy the environment successfully
if [ ! -f ${METADATA_FILE} ]; then
  echo "The environment has been destroyed. Exit 0."
  exit 0
fi

metadata=$(cat ${METADATA_FILE})

integration_additional_resource_group_name=$(echo ${metadata} | jq --raw-output ".additional_resource_group_name // empty")
integration_default_resource_group_name=$(echo ${metadata} | jq --raw-output ".default_resource_group_name // empty")
bats_resource_group_name=$(echo ${metadata} | jq --raw-output ".resource_group_name // empty")
resource_group_names="${integration_additional_resource_group_name} ${integration_default_resource_group_name} ${bats_resource_group_name}"
for resource_group_name  in ${resource_group_names}
do
  exists=$(az group exists --name ${resource_group_name})
  if [ "$exists" = "true" ]
  then
    echo "Deleting ${resource_group_name}"
    az group delete --name ${resource_group_name} --yes
  fi
done
