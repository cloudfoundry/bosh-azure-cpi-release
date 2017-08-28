#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_DEFAULT_GROUP_NAME:?}
: ${AZURE_ADDITIONAL_GROUP_NAME:?}
: ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS:?}
: ${AZURE_DEFAULT_GROUP_NAME_CENTOS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS:?}
: ${AZURE_DEFAULT_GROUP_NAME_WINDOWS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS:?}
: ${AZURE_DEFAULT_GROUP_NAME_WINDOWS_MANAGED_DISKS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS_MANAGED_DISKS:?}
: ${AZURE_REGION_NAME:?}
: ${AZURE_REGION_SHORT_NAME:?}
: ${AZURE_STORAGE_ACCOUNT_NAME:?}
: ${AZURE_STORAGE_ACCOUNT_NAME_MANAGED_DISKS:?}
: ${AZURE_STORAGE_ACCOUNT_NAME_WINDOWS:?}
: ${AZURE_STORAGE_ACCOUNT_NAME_WINDOWS_MANAGED_DISKS:?}
: ${AZURE_VNET_NAME_FOR_BATS:?}
: ${AZURE_VNET_NAME_FOR_LIFECYCLE:?}
: ${AZURE_BOSH_SUBNET_NAME:?}
: ${AZURE_BOSH_SECOND_SUBNET_NAME:?}
: ${AZURE_CF_SUBNET_NAME:?}
: ${AZURE_CF_SECOND_SUBNET_NAME:?}
: ${AZURE_APPLICATION_GATEWAY_NAME:?}

function create_storage_account {
  resource_group_name="$1"
  storage_account_name="$2"
  azure storage account create --location ${AZURE_REGION_SHORT_NAME} --sku-name LRS --kind Storage --resource-group ${resource_group_name} ${storage_account_name}
  storage_account_key=$(azure storage account keys list ${storage_account_name} --resource-group ${resource_group_name} --json | jq '.[0].value' -r)
  azure storage container create --account-name ${storage_account_name} --account-key ${storage_account_key} --container bosh
  azure storage container create --account-name ${storage_account_name} --account-key ${storage_account_key} --permission blob --container stemcell
}

azure login --environment ${AZURE_ENVIRONMENT} --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

set +e

# The additional resource groups must be deleted before the default resource groups, because the disk blobs of VMs in additional RGs are in the storage account of default RGs.
# The storage account can't be deleted before the disk blobs are deleted.
resource_group_names="${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_DEFAULT_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} \
  ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS} ${AZURE_DEFAULT_GROUP_NAME_WINDOWS} ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS_MANAGED_DISKS} ${AZURE_DEFAULT_GROUP_NAME_WINDOWS_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  # Check if the resource group already exists
  echo "azure group show --name ${resource_group_name}"
  azure group show --name ${resource_group_name} > /dev/null 2>&1
  
  if [ $? -eq 0 ]
  then
    echo "azure group delete ${resource_group_name}"
    azure group delete ${resource_group_name} --quiet
  fi
done

set -e

# Create the virtual networks, subnets, and the security groups
for resource_group_name in ${resource_group_names}
do
  echo azure group create ${resource_group_name} ${AZURE_REGION_SHORT_NAME}
  azure group create ${resource_group_name} ${AZURE_REGION_SHORT_NAME}
  cat > network-parameters.json << EOF
  {
    "virtualNetworkNameForBats": {
      "value": "${AZURE_VNET_NAME_FOR_BATS}"
    },
    "virtualNetworkNameForLifecycle": {
      "value": "${AZURE_VNET_NAME_FOR_LIFECYCLE}"
    },
    "subnetNameForBosh": {
      "value": "${AZURE_BOSH_SUBNET_NAME}"
    },
    "secondSubnetNameForBosh": {
      "value": "${AZURE_BOSH_SECOND_SUBNET_NAME}"
    },
    "subnetNameForCloudFoundry": {
      "value": "${AZURE_CF_SUBNET_NAME}"
    },
    "secondSubnetNameForCloudFoundry": {
      "value": "${AZURE_CF_SECOND_SUBNET_NAME}"
    }
  }
EOF
  azure group deployment create ${resource_group_name} --template-file ./bosh-cpi-src/ci/assets/azure/network.json --parameters-file ./network-parameters.json
done

# Create application gateway
openssl genrsa -out fake.domain.key 2048
openssl req -new -x509 -days 365 -key fake.domain.key -out fake.domain.crt -subj "/C=/ST=test/L=test/O=test/OU=test/CN=fake.domain"
openssl pkcs12 -export -out fake.domain.pfx -inkey fake.domain.key -in fake.domain.crt -passout pass:cpilifecycle
CERT_DATA=`base64 fake.domain.pfx | tr -d '\n'`
cat > application-gateway-parameters.json << EOF
  {
    "applicationGatewayName": {
      "value": "${AZURE_APPLICATION_GATEWAY_NAME}"
    },
    "virtualNetworkName": {
      "value": "${AZURE_VNET_NAME_FOR_LIFECYCLE}"
    },
    "systemDomain": {
      "value": "fake.domain"
    },
    "certData": {
      "value": "${CERT_DATA}"
    },
    "certPassword": {
      "value": "cpilifecycle"
    }
  }
EOF
pids=""
resource_group_names="${AZURE_DEFAULT_GROUP_NAME} ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} \
  ${AZURE_DEFAULT_GROUP_NAME_WINDOWS} ${AZURE_DEFAULT_GROUP_NAME_WINDOWS_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  {
    azure group deployment create ${resource_group_name} --template-file ./bosh-cpi-src/ci/assets/azure/application-gateway.json --parameters-file ./application-gateway-parameters.json
  } &
  pids="$pids $!"
done
rm fake.domain.key
rm fake.domain.crt
rm fake.domain.pfx

failed=false
wait $pids || failed=true
if [ $failed = true ]; then
  exit 1
fi

# The public IP AzureCPICI-bosh and AzureCPICI-cf-bats are needed only in the additional resource groups
resource_group_names="${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} \
  ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS} ${AZURE_ADDITIONAL_GROUP_NAME_WINDOWS_MANAGED_DISKS}"
for resource_group_name in ${resource_group_names}
do
  echo azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-bosh --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-bosh --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  echo azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-bats --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-bats --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
done

# Setup the storage account only in the default resource groups
create_storage_account ${AZURE_DEFAULT_GROUP_NAME} ${AZURE_STORAGE_ACCOUNT_NAME}
create_storage_account ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} ${AZURE_STORAGE_ACCOUNT_NAME_MANAGED_DISKS}
create_storage_account ${AZURE_DEFAULT_GROUP_NAME_WINDOWS} ${AZURE_STORAGE_ACCOUNT_NAME_WINDOWS}
create_storage_account ${AZURE_DEFAULT_GROUP_NAME_WINDOWS_MANAGED_DISKS} ${AZURE_STORAGE_ACCOUNT_NAME_WINDOWS_MANAGED_DISKS}
