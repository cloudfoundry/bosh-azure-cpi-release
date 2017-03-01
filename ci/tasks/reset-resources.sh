#!/usr/bin/env bash

set -e

function exit_if_error {
  echo "You should run the task recreate-infrastructure-primary to provision resources on Azure"
  exit 1
}

: ${AZURE_TENANT_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_GROUP_NAME_FOR_VMS:?}
: ${AZURE_GROUP_NAME_FOR_NETWORK:?}
: ${AZURE_STORAGE_ACCOUNT_NAME:?}
: ${AZURE_VNET_NAME_FOR_BATS:?}
: ${AZURE_VNET_NAME_FOR_LIFECYCLE:?}
: ${AZURE_BOSH_SUBNET_NAME:?}
: ${AZURE_BOSH_SECOND_SUBNET_NAME:?}
: ${AZURE_CF_SUBNET_NAME:?}
: ${AZURE_CF_SECOND_SUBNET_NAME:?}

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

set +e

resource_group_names="${AZURE_GROUP_NAME_FOR_VMS} ${AZURE_GROUP_NAME_FOR_NETWORK} ${AZURE_GROUP_NAME_FOR_VMS_MANAGED_DISKS} ${AZURE_GROUP_NAME_FOR_NETWORK_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  echo "Check if the resource group exists"
  echo "azure group list | grep ${resource_group_name}"
  azure group list | grep ${resource_group_name}
  
  if [ $? -eq 1 ]; then
    echo "The task failed because the resource group ${resource_group_name} does not exist"
    exit_if_error
  fi
done

set -e

echo "Check if the needed resources exist"

resource_group_names="${AZURE_GROUP_NAME_FOR_VMS} ${AZURE_GROUP_NAME_FOR_NETWORK} ${AZURE_GROUP_NAME_FOR_VMS_MANAGED_DISKS} ${AZURE_GROUP_NAME_FOR_NETWORK_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  vnets="${AZURE_VNET_NAME_FOR_BATS} ${AZURE_VNET_NAME_FOR_LIFECYCLE}"
  for vnet in ${vnets}
  do
    echo "azure network vnet show --resource-group ${resource_group_name} --name $vnet --json | jq '.name' -r"
    vnet_actual=$(azure network vnet show --resource-group ${resource_group_name} --name ${vnet} --json | jq '.name' -r)
    if [ "${vnet_actual}" != "${vnet}" ]; then
      echo "The task failed because the virtual network ${vnet} does not exist in resource group ${resource_group_name}"
      exit_if_error
    else
      subnets="${AZURE_BOSH_SUBNET_NAME} ${AZURE_BOSH_SECOND_SUBNET_NAME} ${AZURE_CF_SUBNET_NAME} ${AZURE_CF_SECOND_SUBNET_NAME}"
      for subnet in ${subnets}
      do
        echo "azure network vnet subnet show --resource-group ${resource_group_name} --vnet-name ${vnet} --name ${subnet} --json | jq '.name' -r"
        subnet_actual=$(azure network vnet subnet show --resource-group ${resource_group_name} --vnet-name ${vnet} --name ${subnet} --json | jq '.name' -r)
        if [ "${subnet_actual}" != "${subnet}" ]; then
          echo "The task failed because the subnet ${subnet} in virtual network ${vnet} does not exist in resource group ${resource_group_name}"
          exit_if_error
        fi
      done
    fi
  done
  
  public_ips="AzureCPICI-bosh AzureCPICI-cf-lifecycle AzureCPICI-cf-bats"
  for public_ip in ${public_ips}
  do
    echo "azure network public-ip show --resource-group ${resource_group_name} --name ${public_ip} --json | jq '.name' -r"
    public_ip_actual=$(azure network public-ip show --resource-group ${resource_group_name} --name ${public_ip} --json | jq '.name' -r)
    if [ "${public_ip_actual}" != "${public_ip}" ]; then
      echo "The task failed because the public IP ${public_ip} does not exist in resource group ${resource_group_name}"
      exit_if_error
    fi
  done
done

set +e

echo "azure storage account show --resource-group ${AZURE_GROUP_NAME_FOR_VMS} ${AZURE_STORAGE_ACCOUNT_NAME}"
azure storage account show --resource-group ${AZURE_GROUP_NAME_FOR_VMS} ${AZURE_STORAGE_ACCOUNT_NAME}

if [ $? -eq 1 ]; then
  echo "The task failed because the storage account ${AZURE_STORAGE_ACCOUNT_NAME} does not exist in resource group ${AZURE_GROUP_NAME_FOR_VMS}"
  exit_if_error
fi

set -e

AZURE_ACCOUNT_KEY=$(azure storage account keys list ${AZURE_STORAGE_ACCOUNT_NAME} --resource-group ${AZURE_GROUP_NAME_FOR_VMS} --json | jq '.[0].value' -r)
containers="bosh stemcell"
for container in ${containers}
do
  container_actual=$(azure storage container show --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container ${container} --json | jq '.name' -r)
  if [ "${container_actual}" != "${container}" ]; then
    echo "The task failed because the container ${container} does not exist in resource group ${AZURE_GROUP_NAME_FOR_VMS}"
    exit_if_error
  fi
done

echo "Deleting the unneeded resources"

resource_group_names="${AZURE_GROUP_NAME_FOR_VMS} ${AZURE_GROUP_NAME_FOR_NETWORK} ${AZURE_GROUP_NAME_FOR_VMS_MANAGED_DISKS} ${AZURE_GROUP_NAME_FOR_NETWORK_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  vms=$(azure vm list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for vm in ${vms}
  do
    echo "azure vm delete --resource-group ${resource_group_name} --name ${vm}"
    azure vm delete --resource-group ${resource_group_name} --name ${vm} --quiet
  done

  nics=$(azure network nic list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for nic in ${nics}
  do
    echo "azure network nic delete --resource-group ${resource_group_name} --name ${nic}"
    azure network nic delete --resource-group ${resource_group_name} --name ${nic} --quiet
  done

  disks=$(azure managed-disk list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for disk in ${disks}
  do
    echo "azure managed-disk delete --resource-group ${resource_group_name} --name ${disk}"
    azure managed-disk delete --resource-group ${resource_group_name} --name ${disk} --quiet
  done

  images=$(azure managed-image list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for image in ${images}
  do
    echo "azure managed-image delete --resource-group ${resource_group_name} --name ${image}"
    azure managed-image delete --resource-group ${resource_group_name} --name ${image} --quiet
  done

  snapshots=$(azure managed-snapshot list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for snapshot in ${snapshots}
  do
    echo "azure managed-snapshot delete --resource-group ${resource_group_name} --name ${snapshot}"
    azure managed-snapshot delete --resource-group ${resource_group_name} --name ${snapshot} --quiet
  done

  lbs=$(azure network lb list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for lb in ${lbs}
  do
    echo "azure network lb delete --resource-group ${resource_group_name} --name ${lb}"
    azure network lb delete --resource-group ${resource_group_name} --name ${lb} --quiet
  done

  availsets=$(azure availset list --resource-group ${resource_group_name} --json | jq '.[].name' -r)
  for availset in ${availsets}
  do
    echo "azure availset delete --resource-group ${resource_group_name} --name ${availset}"
    azure availset delete --resource-group ${resource_group_name} --name ${availset} --quiet
  done
done

containers="stemcell bosh"
for container in ${containers}
do
  echo "azure storage container delete --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container ${container}"
  azure storage container delete --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container ${container} --quiet
  
  set +e
  count=0
  while [ true ]; do
    sleep 15
    echo "azure storage container create --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container ${container}"
    azure storage container create --account-name ${AZURE_STORAGE_ACCOUNT_NAME} --account-key ${AZURE_ACCOUNT_KEY} --container ${container}
  
    if [ $? == 0 ]; then
      break
    fi
    let count=count+1
    if [ ${count} -gt 10 ]; then
      echo "The task failed because the container ${container} cannot be created"
      exit_if_error
    fi
  done
  set -e
done

echo "The unneeded resources are deleted"
