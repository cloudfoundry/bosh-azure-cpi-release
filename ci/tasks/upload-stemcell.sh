#!/usr/bin/env bash
set -eu -o pipefail

: "${METADATA_FILE:=environment/metadata}"

# outputs
output_dir=$(realpath stemcell-state/)

metadata=$(cat "${METADATA_FILE}")

az cloud set --name "${AZURE_ENVIRONMENT}"
az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" --tenant "${AZURE_TENANT_ID}"
az account set -s "${AZURE_SUBSCRIPTION_ID}"

DEFAULT_RESOURCE_GROUP_NAME=$(echo "${metadata}" | jq -e --raw-output ".default_resource_group_name")
STORAGE_ACCOUNT_NAME=$(echo "${metadata}" | jq -e --raw-output ".storage_account_name")

account_name=${STORAGE_ACCOUNT_NAME}
account_key=$(az storage account keys list --account-name "${account_name}" --resource-group "${DEFAULT_RESOURCE_GROUP_NAME}" \
              | jq '.[0].value' -r)

if [ "${IS_HEAVY_STEMCELL}" == "true" ]; then

  stemcell_id="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
  echo "Using heavy stemcell: '${stemcell_id}'"

  stemcell_path="/tmp/image"
  # Always upload the latest stemcell for lifecycle test
  tar -xf "$(realpath stemcell/*.tgz)" -C /tmp/
  tar -xf ${stemcell_path} -C /tmp/
  az storage blob upload \
    --file /tmp/root.vhd \
    --container-name stemcell \
    --name "${stemcell_id}.vhd" \
    --type page \
    --account-name "${account_name}" \
    --account-key "${account_key}"

  cat > "${output_dir}/stemcell.env" <<EOF
export BOSH_AZURE_STEMCELL_ID="${stemcell_id}"
EOF

else

  stemcell_id="bosh-light-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
  echo "Using light stemcell: '${stemcell_id}'"

  # Use the light stemcell cloud properties to generate metadata in space-separated key=value pairs
  tar -xf "$(realpath stemcell/*.tgz)" -C /tmp/
  stemcell_metadata=$(ruby -r yaml -r json -e '
    data = YAML::load(STDIN.read)
    stemcell_properties = data["cloud_properties"]
    stemcell_properties["hypervisor"]="hyperv"
    metadata=""
    stemcell_properties.each do |key, value|
      if key == "image"
        metadata += "#{key}=#{JSON.dump(value)} "
      else
        metadata += "#{key}=#{value} "
      end
    end
    puts metadata' < /tmp/stemcell.MF)
  dd if=/dev/zero of=/tmp/root.vhd bs=1K count=1
  az storage blob upload \
    --file /tmp/root.vhd \
    --container-name stemcell \
    --name "${stemcell_id}.vhd" \
    --type page \
    --metadata "${stemcell_metadata}" \
    --account-name "${account_name}" \
    --account-key "${account_key}"

  image_urn=$(ruby -r yaml -r json -e '
    data = YAML::load(STDIN.read)
    stemcell_properties = data["cloud_properties"]
    stemcell_properties.each do |key, value|
      if key == "image"
        puts "#{value["publisher"]}:#{value["offer"]}:#{value["sku"]}:#{value["version"]}"
      end
    end' < /tmp/stemcell.MF)
  # Accept legal terms
  echo "Accepting the legal terms of image ${image_urn}"
  az vm image accept-terms --urn "${image_urn}"

  cat > "${output_dir}/stemcell.env" <<EOF
export BOSH_AZURE_STEMCELL_ID="${stemcell_id}"
EOF

fi
