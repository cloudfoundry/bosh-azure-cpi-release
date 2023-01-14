#!/usr/bin/env bash

set -eu

if [[ $(lpass status -q; echo $?) != 0 ]]; then
  echo "Login with lpass first"
  exit 1
fi
FLY="${FLY_CLI:-fly}"

${FLY} -t "${CONCOURSE_TARGET:-bosh-ecosystem}" set-pipeline -p "bosh-azure-cpi" \
    -c ci/pipeline.yml \
    -v ruby_version=$(cat src/bosh_azure_cpi/.ruby-version)
