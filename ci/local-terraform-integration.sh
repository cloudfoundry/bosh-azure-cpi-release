#!/usr/bin/env bash

set -eu -o pipefail

if [[ $(lpass status -q; echo $?) != 0 ]]; then
  echo "Login with lpass first"
  exit 1
fi
bosh interpolate local-terraform-vars.yml --vars-file=<(lpass show -G --sync=now "azure-cpi-bats-concourse-secrets" --notes) | yq read - --tojson > /tmp/terraform.tfvars.json
terraform plan -var-file=/tmp/terraform.tfvars.json -var env_name=azcpi-local-integration assets/terraform/integration