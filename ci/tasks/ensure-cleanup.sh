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

set +e
metadata=$(cat ${METADATA_FILE})

integration_additional_resource_group_name=$(echo ${metadata} | jq -e --raw-output ".additional_resource_group_name")
integration_default_resource_group_name=$(echo ${metadata} | jq -e --raw-output ".default_resource_group_name")
bats_resource_group_name=$(echo ${metadata} | jq -e --raw-output ".resource_group_name")
resource_group_names="${integration_additional_resource_group_name} ${integration_default_resource_group_name} ${bats_resource_group_name}"
for resource_group_name  in ${resource_group_names}
do
  exists=$(az group exists --name ${resource_group_name})
  if [ "$exists" = "true" ]
  then
    az group delete --name ${resource_group_name} --yes
  fi
done
