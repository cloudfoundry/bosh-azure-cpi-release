#!/usr/bin/env bash

source bosh-cpi-release/ci/tasks/utils.sh

# copy 
cp bosh-cpi-release/ci/assets/azure/azuredeploy.json ./azuredeploy.json
pwd
check_param AZURE_CLIENT_ID
check_param AZURE_CLIENT_SECRET
check_param AZURE_GROUP_NAME
check_param AZURE_REGION_NAME
check_param AZURE_REGION_SHORT_NAME
check_param AZURE_BOSH_SUBNET_NAME
check_param AZURE_CF_SUBNET_NAME
check_param AZURE_TENANT_ID

azure login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}

# switch to resource manager mode
echo "azure config mode arm"
azure config mode arm
export_file=azure-exports.sh
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

echo azure group create ${AZURE_GROUP_NAME} ${AZURE_REGION_SHORT_NAME}
azure group create ${AZURE_GROUP_NAME} ${AZURE_REGION_SHORT_NAME}
echo "{ \"location\": { \"value\": \"${AZURE_REGION_NAME}\" }, \"newStorageAccountName\": { \"value\": \"${AZURE_STORAGE_ACCOUNT_NAME}\" }, \"virtualNetworkName\": { \"value\": \"${AZURE_VNET_NAME}\" }, \"subnetNameForBosh\": { \"value\": \"${AZURE_BOSH_SUBNET_NAME}\" }, \"subnetNameForCloudFoundry\": { \"value\": \"${AZURE_CF_SUBNET_NAME}\" } }" > azuredeploy-parameters.json
cat ./azuredeploy-parameters.json
azure group deployment create ${AZURE_GROUP_NAME} --template-file ./azuredeploy.json --parameters-file ./azuredeploy-parameters.json

echo -e "export DIRECTOR=$(azure network public-ip show ${AZURE_GROUP_NAME} pubIP-bosh --json | jq '.ipAddress')" >> $export_file
echo -e "export CF_IP_ADDRESS=$(azure network public-ip show ${AZURE_GROUP_NAME} pubIP-cf --json | jq '.ipAddress')" >> $export_file
echo -e "export AZURE_STORAGE_ACCESS_KEY=$(azure storage account keys list ${AZURE_STORAGE_ACCOUNT_NAME} -g ${AZURE_GROUP_NAME} --json | jq '.storageAccountKeys.key1')" >> $export_file