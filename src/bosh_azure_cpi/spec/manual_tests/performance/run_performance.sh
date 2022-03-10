chruby 3.1.0
source ./run_performance.pri.sh

export SERVICE_HOST_BASE="core.windows.net"

pushd tf
  terraform init
  PREFIX=$(echo "$PREFIX" | tr '[:upper:]' '[:lower:]')
  terraform apply -var prefix="${PREFIX}" \
  -var subscription_id="${SUBSCRIPTION_ID}" \
  -var client_id="${CLIENT_ID}" \
  -var client_secret="${CLIENT_SECRET}"  \
  -var tenant_id="${TENANT_ID}"  \
  -var location="westus"

  export RESOURCE_GROUP=${PREFIX}-rg
  export VNET_NAME=${PREFIX}-vnet
  export SUBNET_NAME=${PREFIX}-bosh-subnet
  default_storage_account=$(echo $PREFIX | sed -e 's/[^0-9a-z]//g')
  default_storage_access_key=$(az storage account keys list -g ${PREFIX}-rg -n ${default_storage_account} | jq .[0].value)

  connection_string="DefaultEndpointsProtocol=https;AccountName=${default_storage_account};AccountKey=${default_storage_access_key};EndpointSuffix=${SERVICE_HOST_BASE}"

  az storage container create --name bosh --connection-string ${connection_string}
  az storage container create --name stemcell --public-access blob --connection-string ${connection_string}
  az storage table create --name stemcells --connection-string ${connection_string}
popd

cat > ./create_db.sql <<EOS
CREATE USER test WITH PASSWORD 'test';
CREATE DATABASE testdb;
GRANT ALL PRIVILEGES ON DATABASE testdb to test;
EOS
psql -f ./create_db.sql

cat > ./cpi.cfg <<EOF
---
azure:
  environment: AzureCloud
  subscription_id: ${SUBSCRIPTION_ID}
  storage_account_name: $default_storage_account
  storage_account_type: Standard_LRS
  resource_group_name: ${RESOURCE_GROUP}
  tenant_id: ${TENANT_ID}
  client_id: ${CLIENT_ID}
  client_secret: ${CLIENT_SECRET}
  ssh_user: vcap
  ssh_public_key: $(cat ~/.ssh/id_rsa.pub)
  default_security_group: ${PREFIX}-bosh-sg
  debug_mode: false
  use_managed_disks: true
  vnet_name: ${VNET_NAME}
  subnet_name: ${SUBNET_NAME}
  perform_times: 1
registry:
  endpoint: http://127.0.0.1:25695
  user: admin
  password: admin
EOF

cat > ./registry.cfg <<EOS
---
loglevel: debug
http:
  port: 25695
  user: admin
  password: admin
db:
  adapter: postgres
  max_connections: 32
  pool_timeout: 10
  host: 127.0.0.1
  database: testdb
  user: test
  password: test
EOS

PROCESS_NUM=$(ps -ef | grep "bosh-registry" | wc -l)
# for degbuging...
if [ $PROCESS_NUM -eq 2 ]; then
    echo "already running."
else
    echo "starting bosh registry."
    bosh-registry -c ./registry.cfg &
fi

if [ "$OFFICIAL_STEMCELL_ID" == "" ];
then
  export STEMCELL_URL=${STEMCELL_URL:-"https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3586.24"}
  wget ${STEMCELL_URL} -O official_stemcell_to_test.tgz
  mkdir -p official_stemcell_folder
  tar -xzf official_stemcell_to_test.tgz -C official_stemcell_folder
  echo "uploading the official image..."
  ruby upload_image.rb "./official_stemcell_folder/image"
  echo "run performance test for the official images..."
  ruby performance.rb -i "./official_stemcell_folder/image" | grep 'perf result,'
else
  echo "run performance test for the official images..."
  ruby performance.rb $OFFICIAL_STEMCELL_ID | grep 'perf result,'
fi

if [ "$MODIFIED_STEMCELL_ID" == "" ];
then
  export STEMCELL_URL=${STEMCELL_URL:-"https://opensourcerelease.blob.core.windows.net/stemcells/bosh-stemcell-2222.25-azure-hyperv-ubuntu-xenial-go_agent.tgz"}
  wget ${STEMCELL_URL} -O modified_stemcell_to_test.tgz
  mkdir -p modified_stemcell_folder
  tar -xzf modified_stemcell_to_test.tgz -C modified_stemcell_folder
  echo "uploading the modified image..."
  ruby upload_image.rb "./modified_stemcell_folder/image"
  echo "run performance test for the modified images..."
  ruby performance.rb -i "./modified_stemcell_folder/image" | grep 'perf result,'
else
  echo "run performance test for the modified images..."
  ruby performance.rb $MODIFIED_STEMCELL_ID | grep 'perf result,'
fi

