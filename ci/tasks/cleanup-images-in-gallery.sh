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

metadata=$(cat ${METADATA_FILE})

compute_gallery_name=$(echo ${metadata} | jq --raw-output ".compute_gallery_name // empty")
default_resource_group_name=$(echo ${metadata} | jq --raw-output ".default_resource_group_name // empty")

exists=$(az sig show --resource-group $default_resource_group_name} --gallery-name $compute_gallery_name || echo "does-not-exist")
if [ "$exists" != "does-not-exist" ]
then
  gallery_images=$(az sig image-definition list --resource-group $default_resource_group_name --gallery-name $compute_gallery_name | jq -r '. | map(.name)[]')
  for gallery_image in $gallery_images; do
    echo "Deleting gallery ${gallery_image}"
    gallery_image_versions=$(az sig image-version list --resource-group $default_resource_group_name --gallery-name $compute_gallery_name --gallery-image-name $gallery_image | jq -r '. | map(.name)[]')
    for gallery_image_version in $gallery_image_versions; do
      echo "Deleting version ${gallery_image_version}"
      az sig image-version delete --resource-group $default_resource_group_name --gallery-name $compute_gallery_name --gallery-image-name $gallery_image --gallery-image-version $gallery_image_version
    done
    az sig image-definition delete --resource-group $default_resource_group_name --gallery-name $compute_gallery_name --gallery-image-name $gallery_image
  done
fi
