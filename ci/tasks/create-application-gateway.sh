#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_APPLICATION_GATEWAY_NAME:?}

: ${METADATA_FILE:=environment/metadata}

metadata=$(cat ${METADATA_FILE})

az cloud set --name ${AZURE_ENVIRONMENT}
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}

# Create application gateway
openssl genrsa -out fake.domain.key 2048
openssl req -new -x509 -days 365 -key fake.domain.key -out fake.domain.crt -subj "/C=/ST=test/L=test/O=test/OU=test/CN=fake.domain"
openssl pkcs12 -export -out fake.domain.pfx -inkey fake.domain.key -in fake.domain.crt -passout pass:cpilifecycle
cert_data=`base64 fake.domain.pfx | tr -d '\n'`

rg_name=$(echo ${metadata} | jq -e --raw-output ".default_resource_group_name")
vnet_name=$(echo ${metadata} | jq -e --raw-output ".vnet_name")
cat > application-gateway-parameters.json << EOF
  {
    "applicationGatewayName": {
      "value": "${AZURE_APPLICATION_GATEWAY_NAME}"
    },
    "virtualNetworkName": {
      "value": "${vnet_name}"
    },
    "systemDomain": {
      "value": "fake.domain"
    },
    "certData": {
      "value": "${cert_data}"
    },
    "certPassword": {
      "value": "cpilifecycle"
    }
  }
EOF
az group deployment create --resource-group ${rg_name} --name "create-application-gateway" --template-file bosh-cpi-src/ci/assets/azure/application-gateway.json --parameters application-gateway-parameters.json

rm fake.domain.key
rm fake.domain.crt
rm fake.domain.pfx
