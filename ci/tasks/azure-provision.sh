#!/usr/bin/env bash

source bosh-cpi-release/ci/tasks/utils.sh

# copy 
cp bosh-cpi-release/ci/assets/azure/azuredeploy.json ./azuredeploy.json
cp bosh-cpi-release/ci/assets/azure/azuredeploy-parameters.json ./azuredeploy-parameters.json

check_param AZURE_USER_NAME
check_param AZURE_USER_PASSWORD
check_param AZURE_GROUP_NAME
check_param AZURE_REGION_NAME

azure login -u ${AZURE_USER_NAME} -p ${AZURE_USER_PASSWORD}

# switch to resource manager mode
echo "azure config mode arm"
azure config mode arm

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

azure group create ${AZURE_GROUP_NAME} ${AZURE_REGION_NAME}
azure group deployment create ${AZURE_GROUP_NAME} --template-file ./azuredeploy.json --parameters-file ./azuredeploy-parameters.json
