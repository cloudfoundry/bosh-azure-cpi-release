#!/usr/bin/env bash


# TODO: Once terraform supports creating `standard` or zonal public ip, we will use terraform to create the resource

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_LOCATION:?}
: ${AZURE_BATS_STANDARD_PUBLIC_IP_NAME:?}

: ${METADATA_FILE:=environment/metadata}

metadata=$(cat ${METADATA_FILE})

az cloud set --name ${AZURE_ENVIRONMENT}
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
az account set -s ${AZURE_SUBSCRIPTION_ID}

rg_name=$(echo ${metadata} | jq -e --raw-output ".resource_group_name")
az network public-ip create --resource-group ${rg_name} --name ${AZURE_BATS_STANDARD_PUBLIC_IP_NAME} --location "${AZURE_LOCATION}" --allocation-method Static --sku Standard

ipaddr=$( az network public-ip show --resource-group ${rg_name} --name ${AZURE_BATS_STANDARD_PUBLIC_IP_NAME}   | jq '.ipAddress' -r )
echo $ipaddr > ipaddrs/ipaddr_${AZURE_BATS_STANDARD_PUBLIC_IP_NAME}
